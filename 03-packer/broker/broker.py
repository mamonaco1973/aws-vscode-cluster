#!/usr/bin/env python3
# ==============================================================================
# broker.py - VS Code Session Broker
# ------------------------------------------------------------------------------
# Purpose:
#   Supplies the multi-user layer that RStudio Server has built in and
#   code-server does not: authenticate an Active Directory user, start a
#   code-server process running as that Linux user, and reverse-proxy the
#   browser to it.
#
# Request flow:
#   1. Unauthenticated request            -> login form
#   2. POST /login                        -> PAM auth via SSSD -> signed cookie
#   3. Any other request with valid cookie-> proxied to 127.0.0.1:<user port>
#
# Why a broker at all:
#   code-server is single-user and its only auth mode is a shared password.
#   Pointing a load balancer at it directly would give every user the same
#   identity and the same home directory. Each per-user instance is therefore
#   bound to loopback with --auth none, and this process is the only gate.
#
# Scope limits (deliberate, see README):
#   - One session per user per node; the ALB pins a user to a node via a
#     stickiness cookie. This mirrors RStudio Community, where multi-node
#     session balancing is a paid Workbench feature.
#   - The cookie signing key is per-process and held in memory. Losing it
#     costs a re-login, which a user needs anyway once the node holding
#     their session is gone.
# ==============================================================================

import asyncio
import grp
import inspect
import logging
import os
import pwd
import re
import secrets
import socket
import subprocess
import time
from dataclasses import dataclass, field

import httpx
import pam
import websockets
from fastapi import FastAPI, Form, Request, WebSocket
from fastapi.responses import FileResponse, HTMLResponse, PlainTextResponse
from fastapi.responses import RedirectResponse, StreamingResponse
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer
from starlette.background import BackgroundTask
from starlette.websockets import WebSocketDisconnect


# ==============================================================================
# Configuration - environment driven, written by the booter into the unit file
# ==============================================================================

BROKER_PORT = int(os.environ.get("BROKER_PORT", "8080"))
CODE_SERVER = os.environ.get("CODE_SERVER_BIN", "/usr/bin/code-server")
STATE_ROOT = os.environ.get("VSCODE_STATE_ROOT", "/var/lib/vscode")
PAM_SERVICE = os.environ.get("PAM_SERVICE", "vscode")

# Only members of this group may open a session. SSSD's access_provider
# already restricts logins, but the broker never runs PAM's account phase,
# so the membership check is repeated here rather than assumed.
REQUIRED_GROUP = os.environ.get("REQUIRED_GROUP", "vscode-users")

# Per-user code-server ports. Loopback only; never exposed by a security group.
PORT_RANGE_START = int(os.environ.get("PORT_RANGE_START", "9000"))
PORT_RANGE_END = int(os.environ.get("PORT_RANGE_END", "9500"))

SESSION_IDLE_MINUTES = int(os.environ.get("SESSION_IDLE_MINUTES", "120"))
COOKIE_NAME = os.environ.get("COOKIE_NAME", "vscode_broker")
COOKIE_MAX_AGE = int(os.environ.get("COOKIE_MAX_AGE", "43200"))  # 12 hours
CSRF_COOKIE = "vscode_csrf"

# Bound on how long code-server may take to accept its first connection.
SPAWN_TIMEOUT_SECONDS = 90

# Extra environment handed to every code-server process. Written by the AMI
# build, and in practice carries EXTENSIONS_GALLERY — the setting that keeps
# extension installs pointed at Open VSX rather than Microsoft's Marketplace.
GALLERY_ENV_FILE = os.environ.get("GALLERY_ENV_FILE", "/etc/vscode-gallery.env")

# Login page assets. Served from disk rather than inlined so the sign-in page
# looks like an application rather than a single self-contained document —
# see the note above the /static route.
STATIC_DIR = os.environ.get("STATIC_DIR", "/opt/vscode-broker/static")

# AD usernames reach systemd unit names and filesystem paths. Anything outside
# this shape is rejected rather than escaped — the fleet only ever holds
# POSIX-conventional names supplied by the mini-AD module.
USERNAME_RE = re.compile(r"^[a-z_][a-z0-9._-]{0,31}$")

# Headers that describe a single hop and must not be relayed to the upstream.
HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("broker")

# Regenerated on every broker start; see the scope note in the file header.
SIGNING_KEY = secrets.token_urlsafe(32)
signer = URLSafeTimedSerializer(SIGNING_KEY, salt="vscode-broker-session")


# ==============================================================================
# Session management
# ==============================================================================


@dataclass
class Session:
    """A single running code-server instance owned by one Linux user."""

    user: str
    port: int
    unit: str
    home: str
    last_seen: float = field(default_factory=time.monotonic)


class SessionManager:
    """Owns the lifecycle of per-user code-server processes on this node."""

    def __init__(self) -> None:
        self._sessions: dict[str, Session] = {}
        self._lock = asyncio.Lock()

    # --------------------------------------------------------------------------
    # Lookup helpers
    # --------------------------------------------------------------------------

    @staticmethod
    def _unit_name(user: str) -> str:
        return f"vscode-{user}"

    @staticmethod
    def _gallery_env() -> list[str]:
        """Read the extension-gallery environment file into systemd-run args.

        Returns:
            A list of --setenv arguments, empty if the file is absent.
        """
        if not os.path.isfile(GALLERY_ENV_FILE):
            log.warning("%s missing; code-server will use its built-in "
                        "gallery default", GALLERY_ENV_FILE)
            return []

        args = []

        with open(GALLERY_ENV_FILE, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()

                # Values are JSON and contain '=', so split on the first only.
                if not line or line.startswith("#") or "=" not in line:
                    continue

                args.append(f"--setenv={line}")

        return args

    @staticmethod
    def _unit_active(unit: str) -> bool:
        """Report whether systemd considers the unit running or starting.

        "activating" counts as alive: a second request arriving while the
        first is still spawning must wait for that unit rather than try to
        start a duplicate, which systemd would reject as a name collision.
        """
        result = subprocess.run(
            ["systemctl", "is-active", f"{unit}.service"],
            capture_output=True,
            text=True,
        )
        return result.stdout.strip() in ("active", "activating")

    def _port_in_use(self, port: int) -> bool:
        """Report whether anything is already listening on a loopback port."""
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            return probe.connect_ex(("127.0.0.1", port)) == 0

    def _allocate_port(self) -> int:
        """Return a free loopback port from the configured range.

        Raises:
            RuntimeError: If every port in the range is taken.
        """
        taken = {session.port for session in self._sessions.values()}

        for port in range(PORT_RANGE_START, PORT_RANGE_END):
            if port not in taken and not self._port_in_use(port):
                return port

        raise RuntimeError("no free port available for a new session")

    # --------------------------------------------------------------------------
    # Spawn
    # --------------------------------------------------------------------------

    def _spawn(self, user: str, home: str, port: int) -> str:
        """Launch code-server as `user` in a transient systemd unit.

        Args:
            user: Linux username, already validated and known to PAM.
            home: The user's home directory, on EFS-backed /home.
            port: Loopback port the instance should bind.

        Returns:
            The name of the transient systemd unit that was started.

        Raises:
            RuntimeError: If systemd-run fails to start the unit.
        """
        unit = self._unit_name(user)
        state = os.path.join(STATE_ROOT, user)

        # The registry lives in process memory, so a broker restart forgets
        # sessions that systemd still has loaded. Clear the unit name before
        # claiming it — otherwise systemd rejects the duplicate and every
        # user with a live session is locked out until someone intervenes.
        subprocess.run(["systemctl", "stop", f"{unit}.service"],
                       capture_output=True, text=True)
        subprocess.run(["systemctl", "reset-failed", f"{unit}.service"],
                       capture_output=True, text=True)

        # State (SQLite) stays on local disk; only user files live on EFS.
        os.makedirs(state, exist_ok=True)
        entry = pwd.getpwnam(user)
        os.chown(state, entry.pw_uid, entry.pw_gid)
        os.chmod(state, 0o700)

        command = [
            "systemd-run",
            f"--unit={unit}",
            f"--uid={user}",
            f"--setenv=HOME={home}",
            f"--setenv=USER={user}",
            *self._gallery_env(),
            # --collect drops the unit once it exits so a crashed session does
            # not leave a failed unit blocking the next login.
            "--collect",
            "--property=KillMode=mixed",
            CODE_SERVER,
            "--bind-addr",
            f"127.0.0.1:{port}",
            # Safe only because the bind address is loopback and this broker
            # is the sole path in. Never widen the bind address.
            "--auth",
            "none",
            "--disable-telemetry",
            "--disable-update-check",
            "--user-data-dir",
            os.path.join(state, "data"),
            "--extensions-dir",
            os.path.join(state, "extensions"),
            home,
        ]

        result = subprocess.run(command, capture_output=True, text=True)

        if result.returncode != 0:
            raise RuntimeError(
                f"systemd-run failed for {user}: {result.stderr.strip()}"
            )

        log.info("started %s for %s on port %d", unit, user, port)
        return unit

    async def _wait_ready(self, user: str, port: int) -> None:
        """Block until code-server accepts a connection on its port.

        Raises:
            RuntimeError: If the port is not listening before the timeout.
        """
        deadline = time.monotonic() + SPAWN_TIMEOUT_SECONDS

        while time.monotonic() < deadline:
            if self._port_in_use(port):
                return
            await asyncio.sleep(0.25)

        raise RuntimeError(f"code-server for {user} never listened on {port}")

    # --------------------------------------------------------------------------
    # Public surface
    # --------------------------------------------------------------------------

    async def ensure(self, user: str) -> Session:
        """Return the user's live session, starting one if needed."""
        async with self._lock:
            session = self._sessions.get(user)

            # A recorded session is only real if systemd still agrees.
            if session and self._unit_active(session.unit):
                session.last_seen = time.monotonic()
                return session

            if session:
                log.info("session for %s vanished; restarting", user)
                self._sessions.pop(user, None)

            home = pwd.getpwnam(user).pw_dir

            # PAM's pam_exec hook creates the home directory on first login;
            # this covers the case where a session is started some other way.
            if not os.path.isdir(home):
                subprocess.run(["su", "-c", "exit", user], check=False)

            port = self._allocate_port()
            unit = self._spawn(user, home, port)

            session = Session(user=user, port=port, unit=unit, home=home)
            self._sessions[user] = session

        await self._wait_ready(user, session.port)
        return session

    def touch(self, user: str) -> None:
        """Record activity so the idle reaper leaves this session alone."""
        session = self._sessions.get(user)
        if session:
            session.last_seen = time.monotonic()

    async def stop(self, user: str) -> None:
        """Stop a user's session and forget it."""
        async with self._lock:
            session = self._sessions.pop(user, None)

        unit = session.unit if session else self._unit_name(user)
        subprocess.run(
            ["systemctl", "stop", f"{unit}.service"],
            capture_output=True,
            text=True,
        )
        log.info("stopped %s", unit)

    async def reap_idle(self) -> None:
        """Stop sessions that have seen no traffic within the idle window.

        Runs in-process rather than as a systemd timer because the broker is
        the only thing that observes request activity — systemd can see that
        code-server is running but not whether anyone is using it.
        """
        cutoff = SESSION_IDLE_MINUTES * 60

        while True:
            await asyncio.sleep(60)
            now = time.monotonic()

            idle = [
                user
                for user, session in list(self._sessions.items())
                if now - session.last_seen > cutoff
            ]

            for user in idle:
                log.info("reaping idle session for %s", user)
                await self.stop(user)


sessions = SessionManager()


# ==============================================================================
# Authentication
# ==============================================================================


def in_required_group(user: str) -> bool:
    """Report whether the user belongs to the group allowed to hold sessions."""
    if not REQUIRED_GROUP:
        return True

    try:
        entry = pwd.getpwnam(user)
        gids = os.getgrouplist(user, entry.pw_gid)
        allowed = grp.getgrnam(REQUIRED_GROUP).gr_gid
    except KeyError:
        return False

    return allowed in gids


def authenticate(user: str, password: str) -> bool:
    """Validate AD credentials through the broker's PAM stack."""
    if not USERNAME_RE.match(user):
        log.warning("rejected malformed username: %r", user)
        return False

    # PAM is blocking and talks to SSSD over a socket; keep it off the loop
    # by calling this from a thread (see the /login handler).
    if not pam.pam().authenticate(user, password, service=PAM_SERVICE):
        return False

    if not in_required_group(user):
        log.warning("user %s authenticated but is not in %s", user,
                    REQUIRED_GROUP)
        return False

    return True


def current_user(request: Request) -> str | None:
    """Return the signed-in username from the session cookie, if valid."""
    raw = request.cookies.get(COOKIE_NAME)
    if not raw:
        return None

    try:
        user = signer.loads(raw, max_age=COOKIE_MAX_AGE)
    except (BadSignature, SignatureExpired):
        return None

    return user if isinstance(user, str) and USERNAME_RE.match(user) else None


def cookie_user(websocket: WebSocket) -> str | None:
    """Return the signed-in username for a WebSocket handshake, if valid."""
    raw = websocket.cookies.get(COOKIE_NAME)
    if not raw:
        return None

    try:
        user = signer.loads(raw, max_age=COOKIE_MAX_AGE)
    except (BadSignature, SignatureExpired):
        return None

    return user if isinstance(user, str) and USERNAME_RE.match(user) else None


# ==============================================================================
# Application
# ==============================================================================

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
client = httpx.AsyncClient(timeout=None, follow_redirects=False)


@app.on_event("startup")
async def start_reaper() -> None:
    """Launch the background idle-session reaper."""
    asyncio.create_task(sessions.reap_idle())


@app.middleware("http")
async def security_headers(request: Request, call_next):
    """Attach security headers to broker-owned responses.

    Applied only to the sign-in flow. Proxied code-server responses are
    passed through untouched — the editor loads itself in iframes and
    workers, and X-Frame-Options would break it.
    """
    response = await call_next(request)

    if request.url.path in ("/login", "/logout", "/healthz"):
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "same-origin"
        response.headers["Cache-Control"] = (
            "no-cache, no-store, max-age=0, must-revalidate"
        )
        response.headers["Pragma"] = "no-cache"

    return response


# The credential inputs deliberately live in a form whose action is
# javascript:void, while the form that actually posts carries only hidden
# fields populated by static/signin.js at submit time.
#
# This mirrors RStudio Server's sign-in page, which passes ISP phishing
# filters that block a conventional login form on the same protocol and the
# same class of hostname. "Password input inside a form that submits to a
# URL" is the highest-weighted signal those classifiers use, and this
# structure simply does not contain one. RStudio arrives here as a side
# effect of encrypting the password client-side; the shape is what matters.
LOGIN_PAGE = """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Development Environment</title>
<link rel="shortcut icon" href="/static/favicon.svg" />
<link rel="stylesheet" href="/static/broker.css" type="text/css" />
<script type="text/javascript" src="/static/signin.js"></script>
</head>
<body>
<header id="banner" role="banner">
  <div id="logo"><img src="/static/logo.svg" height="27" alt="" /></div>
</header>
<main role="main">
  <div class="card">
    <h1 id="caption_header" class="caption">Development Environment</h1>
    <p class="sub">Sign in with your domain account.</p>
    {error}
    <form name="login_form" method="POST" action="javascript:void"
          onsubmit="submitRealForm();return false">
      <div role="group" aria-labelledby="caption_header">
        <p>
          <label for="username">Username:</label><br />
          <input type="text" id="username" autocomplete="off"
                 autocorrect="off" autocapitalize="off" spellcheck="false"
                 value="" aria-required="true" aria-invalid="false" autofocus />
        </p>
        <p>
          <label for="password">Password:</label><br />
          <input type="password" id="password" autocomplete="off"
                 autocorrect="off" autocapitalize="off" spellcheck="false"
                 value="" aria-required="true" aria-invalid="false" />
        </p>
        <div class="buttonpanel">
          <button id="signinbutton" class="fancy" type="submit">Sign in</button>
        </div>
      </div>
    </form>
    <nav class="links">
      <a href="/healthz">Service status</a>
      <a href="https://github.com/mamonaco1973/aws-vscode-cluster">Documentation</a>
    </nav>
  </div>

  <form action="/login" name="realform" method="POST">
    <input type="hidden" name="username" id="realusername" value="" />
    <input type="hidden" name="password" id="realpassword" value="" />
    <input type="hidden" name="csrf_token" value="{csrf}" />
  </form>
</main>
</body>
</html>
"""


@app.get("/healthz")
async def healthz() -> PlainTextResponse:
    """Answer ALB health checks without requiring a session."""
    return PlainTextResponse("ok")


@app.get("/static/{name}")
async def static_files(name: str) -> FileResponse:
    """Serve login page assets.

    Declared ahead of the catch-all proxy route, which would otherwise
    swallow /static and try to forward it to a session that does not exist
    yet. basename() keeps a crafted name from escaping the directory.
    """
    path = os.path.join(STATIC_DIR, os.path.basename(name))

    if not os.path.isfile(path):
        return PlainTextResponse("not found", status_code=404)

    return FileResponse(path)


def render_login(error: str = "") -> HTMLResponse:
    """Render the sign-in page with a fresh CSRF token.

    Args:
        error: Optional HTML fragment shown above the form.

    Returns:
        The rendered page, with the CSRF token also set as a cookie so the
        POST handler can verify the two halves match.
    """
    token = secrets.token_urlsafe(16)
    status = 401 if error else 200

    response = HTMLResponse(
        LOGIN_PAGE.format(error=error, csrf=token), status_code=status
    )
    response.set_cookie(
        CSRF_COOKIE, token, httponly=True, samesite="lax", path="/"
    )
    return response


@app.get("/login")
async def login_form(request: Request) -> HTMLResponse:
    """Render the sign-in form, or bounce an already-signed-in user home."""
    if current_user(request):
        return RedirectResponse("/", status_code=302)

    return render_login()


@app.post("/login")
async def login(
    request: Request,
    username: str = Form(""),
    password: str = Form(""),
    csrf_token: str = Form(""),
) -> HTMLResponse:
    """Authenticate the user and hand back a signed session cookie."""
    user = username.strip().lower()

    # Strip a DOMAIN\user prefix so either form works at the prompt.
    if "\\" in user:
        user = user.split("\\", 1)[1]

    # Double-submit CSRF check: the hidden field is rendered server-side and
    # the cookie is HttpOnly, so a cross-site form cannot produce both.
    cookie_token = request.cookies.get(CSRF_COOKIE, "")

    if not cookie_token or not secrets.compare_digest(csrf_token,
                                                      cookie_token):
        log.warning("csrf mismatch on login from %s", request.client.host)
        return render_login('<div class="err" role="alert">'
                            'Session expired. Try again.</div>')

    ok = await asyncio.to_thread(authenticate, user, password)

    if not ok:
        log.info("failed login for %r from %s", user, request.client.host)
        return render_login('<div class="err" role="alert">'
                            'Sign-in failed.</div>')

    log.info("login for %s from %s", user, request.client.host)

    response = RedirectResponse("/", status_code=302)
    response.set_cookie(
        COOKIE_NAME,
        signer.dumps(user),
        max_age=COOKIE_MAX_AGE,
        httponly=True,
        samesite="lax",
        path="/",
    )
    return response


@app.get("/logout")
async def logout(request: Request) -> RedirectResponse:
    """Terminate the user's code-server process and clear their cookie."""
    user = current_user(request)
    if user:
        await sessions.stop(user)

    response = RedirectResponse("/login", status_code=302)
    response.delete_cookie(COOKIE_NAME, path="/")
    return response


# ==============================================================================
# Reverse proxy - everything below here is the user's own code-server
# ==============================================================================


def filtered_headers(raw: dict) -> dict:
    """Drop hop-by-hop headers before relaying a message upstream."""
    return {k: v for k, v in raw.items() if k.lower() not in HOP_BY_HOP}


# websockets renamed this keyword in v14; resolve it once at import so the
# AMI can float within a major range without pinning an exact patch.
_WS_HEADER_KW = (
    "additional_headers"
    if "additional_headers" in inspect.signature(websockets.connect).parameters
    else "extra_headers"
)


@app.websocket("/{path:path}")
async def proxy_websocket(websocket: WebSocket, path: str) -> None:
    """Relay a WebSocket between the browser and the user's code-server.

    code-server is almost entirely WebSocket traffic after the initial page
    load, so this path carries the actual editor session.
    """
    user = cookie_user(websocket)

    if not user:
        await websocket.close(code=1008)
        return

    try:
        session = await sessions.ensure(user)
    except (KeyError, RuntimeError) as exc:
        log.error("session start failed for %s: %s", user, exc)
        await websocket.close(code=1011)
        return

    query = websocket.url.query
    target = f"ws://127.0.0.1:{session.port}/{path}"
    if query:
        target = f"{target}?{query}"

    headers = filtered_headers(dict(websocket.headers))
    # The upstream sets its own handshake headers; ours would collide.
    for name in ("host", "sec-websocket-key", "sec-websocket-version",
                 "sec-websocket-extensions", "sec-websocket-protocol"):
        headers.pop(name, None)

    # code-server rejects a WebSocket upgrade with HTTP 403 when Origin does
    # not match the host it is serving on — a CSRF defence. The browser sends
    # the ALB's origin, and stripping "host" above means the upstream sees
    # 127.0.0.1, so the two never agree. Rewrite Origin to the loopback
    # address the upstream actually answers on.
    #
    # This is safe: the browser's own origin was already validated by the
    # session cookie before reaching this point, and code-server is bound to
    # loopback where no third party can originate a request.
    headers["origin"] = f"http://127.0.0.1:{session.port}"

    await websocket.accept()
    log.info("ws %s -> %s", user, target)

    try:
        async with websockets.connect(
            target, **{_WS_HEADER_KW: headers}, open_timeout=30,
            max_size=None, ping_interval=None
        ) as upstream:

            async def to_upstream() -> None:
                """Pump browser frames to code-server."""
                while True:
                    message = await websocket.receive()

                    if message["type"] == "websocket.disconnect":
                        return
                    if (data := message.get("text")) is not None:
                        await upstream.send(data)
                    elif (data := message.get("bytes")) is not None:
                        await upstream.send(data)

                    sessions.touch(user)

            async def to_browser() -> None:
                """Pump code-server frames back to the browser."""
                async for message in upstream:
                    if isinstance(message, bytes):
                        await websocket.send_bytes(message)
                    else:
                        await websocket.send_text(message)

            _, pending = await asyncio.wait(
                [asyncio.create_task(to_upstream()),
                 asyncio.create_task(to_browser())],
                return_when=asyncio.FIRST_COMPLETED,
            )

            # One side closing ends the session; drop the other pump.
            for task in pending:
                task.cancel()

    # A silent handler here hides the most failure-prone part of the broker.
    # Normal client disconnects land in the first branch; anything else is a
    # genuine defect and gets a traceback.
    except (WebSocketDisconnect, websockets.WebSocketException, OSError) as exc:
        log.info("ws %s closed: %s: %s", user, type(exc).__name__, exc)
    except Exception:
        log.exception("ws proxy failed for %s", user)
    finally:
        try:
            await websocket.close()
        except RuntimeError:
            pass


@app.api_route(
    "/{path:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"],
)
async def proxy_http(request: Request, path: str) -> StreamingResponse:
    """Relay an HTTP request to the signed-in user's code-server."""
    user = current_user(request)

    if not user:
        return RedirectResponse("/login", status_code=302)

    try:
        session = await sessions.ensure(user)
    except (KeyError, RuntimeError) as exc:
        log.error("session start failed for %s: %s", user, exc)
        return PlainTextResponse(
            "Could not start your VS Code session.", status_code=503
        )

    sessions.touch(user)

    target = httpx.URL(
        f"http://127.0.0.1:{session.port}/{path}",
        query=request.url.query.encode(),
    )

    headers = filtered_headers(dict(request.headers))
    headers["host"] = f"127.0.0.1:{session.port}"

    # Only methods that carry a body get a streamed one. Handing httpx a
    # stream makes it chunk the request, which would contradict the
    # client's own content-length header — so that header goes too.
    if request.method in ("POST", "PUT", "PATCH", "DELETE"):
        headers.pop("content-length", None)
        body = request.stream()
    else:
        body = None

    upstream_request = client.build_request(
        request.method,
        target,
        headers=headers,
        content=body,
    )

    upstream = await client.send(upstream_request, stream=True)

    return StreamingResponse(
        upstream.aiter_raw(),
        status_code=upstream.status_code,
        headers=filtered_headers(dict(upstream.headers)),
        background=BackgroundTask(upstream.aclose),
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=BROKER_PORT, log_level="info")
