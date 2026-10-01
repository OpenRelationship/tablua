// Shroomi's own behaviour, reviewed like every script a page may load: the page itself has none. It does what
// Basecoat's templates do with inline handlers, from data- attributes instead, because a page's inline script
// never runs.
//   <button data-open="id">     shows <dialog id="id"> as a modal
//   <button data-close="id">    closes it; a click on the dialog's backdrop closes it too
(function () {
  "use strict";
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
