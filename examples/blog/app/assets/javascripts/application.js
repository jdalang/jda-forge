// Blog application JavaScript

document.addEventListener("DOMContentLoaded", function () {
  // Auto-dismiss flash messages after 4 seconds
  var flashes = document.querySelectorAll(".flash-notice, .flash-alert");
  flashes.forEach(function (el) {
    setTimeout(function () {
      el.style.transition = "opacity 0.4s";
      el.style.opacity = "0";
      setTimeout(function () { el.remove(); }, 400);
    }, 4000);
  });

  // Confirm before delete
  document.querySelectorAll("form[data-confirm]").forEach(function (form) {
    form.addEventListener("submit", function (e) {
      if (!confirm(form.dataset.confirm)) { e.preventDefault(); }
    });
  });
});
