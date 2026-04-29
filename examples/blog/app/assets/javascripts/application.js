// Forge Blog — application JavaScript

document.addEventListener("DOMContentLoaded", function () {

  // Auto-dismiss success alerts after 4 s
  document.querySelectorAll(".alert-success").forEach(function (el) {
    setTimeout(function () {
      var bsAlert = bootstrap.Alert.getOrCreateInstance(el);
      bsAlert.close();
    }, 4000);
  });

  // Confirm before delete forms
  document.querySelectorAll("form[data-confirm]").forEach(function (form) {
    form.addEventListener("submit", function (e) {
      if (!confirm(form.dataset.confirm || "Are you sure?")) {
        e.preventDefault();
      }
    });
  });

  // Auto-grow textareas
  document.querySelectorAll("textarea").forEach(function (ta) {
    ta.addEventListener("input", function () {
      ta.style.height = "auto";
      ta.style.height = (ta.scrollHeight + 2) + "px";
    });
  });

  // Highlight active nav link
  var path = window.location.pathname;
  document.querySelectorAll(".navbar-nav .nav-link").forEach(function (a) {
    if (a.getAttribute("href") === path) {
      a.classList.add("active", "fw-semibold");
    }
  });
});
