// Polls the broker until the user's code-server instance is listening, then
// forwards to the editor. The session is spawned in the background by
// /session-status, so this page loads instantly rather than waiting on it.
(function () {
  var POLL_MS = 1000;
  var GIVE_UP_MS = 120000;
  var started = Date.now();

  function fail(message) {
    var box = document.getElementById("failure");
    box.textContent = message;
    box.style.display = "block";
    document.getElementById("status").textContent =
      "Your session could not be started.";
    var spinner = document.querySelector(".spinner");
    if (spinner) spinner.style.display = "none";
  }

  function poll() {
    if (Date.now() - started > GIVE_UP_MS) {
      fail("Timed out waiting for the session to start. Try signing in again.");
      return;
    }

    fetch("/session-status", { credentials: "same-origin" })
      .then(function (r) {
        if (r.status === 401) {
          window.location = "/login";
          return null;
        }
        return r.json();
      })
      .then(function (data) {
        if (!data) return;

        if (data.state === "ready") {
          window.location = "/";
        } else if (data.state.indexOf("error") === 0) {
          fail(data.state);
        } else {
          setTimeout(poll, POLL_MS);
        }
      })
      .catch(function () {
        // Transient network blips are expected while the node is busy.
        setTimeout(poll, POLL_MS);
      });
  }

  window.addEventListener("load", poll);
})();
