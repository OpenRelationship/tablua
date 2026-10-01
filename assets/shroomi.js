// Shroomi's own behaviour, reviewed like every script a page may load: the page itself has none. It does what
// Basecoat's templates do with inline handlers, from data- attributes instead, because a page's inline script
// never runs.
//   <button data-open="id">     shows <dialog id="id"> as a modal
//   <button data-close="id">    closes it; a click on the dialog's backdrop closes it too
//   <html data-theme="auto">    is dark while the person's system is (Basecoat's .dark), and follows it as it
//                               changes; loaded in the head without defer, so the page never flashes light
(function () {
  "use strict";
  var root = document.documentElement;
  if (root.getAttribute("data-theme") === "auto" && window.matchMedia) {
    var dark = window.matchMedia("(prefers-color-scheme: dark)");
    var follow = function () { root.classList.toggle("dark", dark.matches); };
    follow();
    if (dark.addEventListener) dark.addEventListener("change", follow);
  }
  document.addEventListener("click", function (event) {
    var opener = event.target.closest("[data-open]");
    if (opener) {
      var d = document.getElementById(opener.getAttribute("data-open"));
      if (d && d.tagName === "DIALOG" && !d.open) d.showModal();
      return;
    }
    var closer = event.target.closest("[data-close]");
    if (closer) {
      var c = document.getElementById(closer.getAttribute("data-close"));
      if (c && c.tagName === "DIALOG") c.close();
      return;
    }
    if (event.target.tagName === "DIALOG" && event.target.hasAttribute("data-shroomi-dialog")) event.target.close();
  });
})();
