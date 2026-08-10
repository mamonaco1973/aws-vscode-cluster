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

  function build() {
    var button = document.createElement("button");
    button.id = "broker-signout";
    button.type = "button";
    button.title = "Sign out and stop your session";
    button.setAttribute("aria-label", "Sign out");
    button.textContent = "Sign out";
    button.addEventListener("click", openModal);

    document.body.appendChild(button);
  }

  if (document.readyState === "loading") {
    window.addEventListener("DOMContentLoaded", build);
  } else {
    build();
  }
})();
