// Adds a sign-out control to the editor.
//
// code-server has no notion of the broker's session, so this is the only
// affordance a user has to end it. Confirmation matters: signing out stops
// their code-server process, so unsaved editor state is lost.
(function () {
  var overlay = null;
  var lastFocus = null;

  function closeModal() {
    if (!overlay) return;
    overlay.remove();
    overlay = null;
    document.removeEventListener("keydown", onKeydown, true);
    if (lastFocus) lastFocus.focus();
  }

  function onKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      closeModal();
      return;
    }

    // Trap focus inside the dialog — the editor behind it is still a live
    // tab stop otherwise, and Tab would wander into the file tree.
    if (event.key === "Tab" && overlay) {
      var stops = overlay.querySelectorAll("button");
      var first = stops[0];
      var last = stops[stops.length - 1];

      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
  }

  function openModal() {
    if (overlay) return;
    lastFocus = document.activeElement;

    overlay = document.createElement("div");
    overlay.id = "broker-modal-overlay";

    var dialog = document.createElement("div");
    dialog.id = "broker-modal";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    dialog.setAttribute("aria-labelledby", "broker-modal-title");

    var title = document.createElement("h2");
    title.id = "broker-modal-title";
    title.textContent = "Sign out?";

    var text = document.createElement("p");
    text.textContent =
      "This stops your session. Files saved to your home directory are " +
      "kept. Anything unsaved in the editor will be lost.";

    var actions = document.createElement("div");
    actions.className = "broker-modal-actions";

    var cancel = document.createElement("button");
    cancel.type = "button";
    cancel.className = "broker-btn-secondary";
    cancel.textContent = "Cancel";
    cancel.addEventListener("click", closeModal);

    var confirm = document.createElement("button");
    confirm.type = "button";
    confirm.className = "broker-btn-primary";
    confirm.textContent = "Sign out";
    confirm.addEventListener("click", function () {
      confirm.disabled = true;
      confirm.textContent = "Signing out...";
      window.location = "/logout";
    });

    actions.appendChild(cancel);
    actions.appendChild(confirm);
    dialog.appendChild(title);
    dialog.appendChild(text);
    dialog.appendChild(actions);
    overlay.appendChild(dialog);

    // Clicking the backdrop dismisses; clicks inside must not bubble to it.
    overlay.addEventListener("click", function (event) {
      if (event.target === overlay) closeModal();
    });

    document.body.appendChild(overlay);
    document.addEventListener("keydown", onKeydown, true);
    cancel.focus();
  }

  // Title bar regions, best host first. code-server has renamed these
  // across releases, so fall through rather than depend on one selector.
  // Every placement puts the button immediately RIGHT of the control that
  // is already there: "end" appends after the icon in the left group,
  // "after-first" does the same on the fallback hosts, where the left
  // group is not its own element and first-child would land left of it.
  var HOSTS = [
    { sel: ".monaco-workbench .part.titlebar .titlebar-left", place: "end" },
    { sel: ".monaco-workbench .part.titlebar .titlebar-container",
      place: "after-first" },
    { sel: ".monaco-workbench .part.titlebar", place: "after-first" }
  ];

  var MOUNT_TIMEOUT_MS = 20000;

  var button = null;
  var deadline = 0;

  // True between pointerdown and pointerup on the button. Relocating the
  // node in that window makes the browser drop the click entirely, which
  // shows up as a button that only works some of the time.
  var interacting = false;

  function findHost() {
    for (var i = 0; i < HOSTS.length; i++) {
      var el = document.querySelector(HOSTS[i].sel);
      if (el) return { el: el, place: HOSTS[i].place };
    }
    return null;
  }

  function build() {
    var el = document.createElement("button");
    el.id = "broker-signout";
    el.type = "button";
    el.title = "Sign out and stop your session";
    el.setAttribute("aria-label", "Sign out");

    // Inline SVG rather than a codicon: the icon font is code-server's,
    // and its glyph names are not a stable contract for us.
    el.innerHTML =
      '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" ' +
      'stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" ' +
      'aria-hidden="true"><path d="M6 14H3a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1h3"/>' +
      '<path d="m10.5 11 3-3-3-3"/><path d="M13.5 8H6"/></svg>' +
      "<span>Sign out</span>";

    el.addEventListener("click", openModal);

    el.addEventListener("pointerdown", function () {
      interacting = true;
    });

    // Clear on the document, not the button: a pointerup that lands outside
    // the button would otherwise leave the guard stuck on forever.
    document.addEventListener("pointerup", function () {
      interacting = false;
    });
    document.addEventListener("pointercancel", function () {
      interacting = false;
    });

    return el;
  }

  // Mount into the title bar, or float if it never shows up. Returns true
  // once the control is parented somewhere and needs no further attempts.
  function mount() {
    if (!button) button = build();

    var host = findHost();

    if (host) {
      // Never relocate mid-click; the guard costs at most one 5s tick.
      if (button.parentNode !== host.el && !interacting) {
        button.classList.remove("broker-floating");

        if (host.place === "end") {
          host.el.appendChild(button);
        } else if (host.el.firstElementChild) {
          // After the first existing control, not before it.
          host.el.insertBefore(button, host.el.firstElementChild.nextSibling);
        } else {
          host.el.appendChild(button);
        }
      }
      return true;
    }

    // The workbench boots well after DOMContentLoaded; keep waiting before
    // conceding. Losing the button entirely would strand the session.
    if (Date.now() < deadline) return false;

    if (!button.isConnected) {
      button.classList.add("broker-floating");
      document.body.appendChild(button);
    }
    return true;
  }

  // Deliberately does NOT compare against findHost(): that re-queries and
  // returns a different element object whenever the workbench re-renders
  // the title bar, so an identity check reports "not settled" forever and
  // the guard below relocates the button every tick. Moving it mid-click
  // makes the browser drop the click. Being somewhere in the title bar is
  // the whole requirement.
  function settled() {
    if (!button || !button.isConnected) return false;
    return !!button.closest(".part.titlebar");
  }

  // Cheap long-lived guard. A subtree observer on <body> would fire on
  // essentially every workbench render, so watch on an interval instead
  // and only touch the DOM when the button has actually gone missing.
  function watch() {
    setInterval(function () {
      if (!settled()) mount();
    }, 5000);
  }

  function start() {
    deadline = Date.now() + MOUNT_TIMEOUT_MS;

    if (mount()) {
      watch();
      return;
    }

    // Until the workbench renders there is nothing to mount into, so watch
    // the DOM closely — but only for that window, then drop to the guard.
    var observer = new MutationObserver(function () {
      if (settled()) return;

      if (mount()) {
        observer.disconnect();
        watch();
      }
    });

    observer.observe(document.body, { childList: true, subtree: true });
  }

  if (document.readyState === "loading") {
    window.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
