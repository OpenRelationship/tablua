// Shroomi's own behaviour, reviewed like every script a page may load: the page itself has none. It does what
// Basecoat's templates do with inline handlers, from data- attributes instead, because a page's inline script
// never runs.
//   <button data-open="id">     shows <dialog id="id"> as a modal
//   <button data-close="id">    closes it; a click on the dialog's backdrop closes it too
//   <html data-theme="auto">    is dark while the person's system is (Basecoat's .dark), and follows it as it
//                               changes; loaded in the head without defer, so the page never flashes light
//   an htmx answer to an element with data-morph (an action of a .lui page) is a whole page: it is merged into this
//   one with idiomorph, so focus and scroll stay, and what the person typed and has not sent stays, in the field
//   they are in and any other (the form an action sent takes the page's answer). A body with data-part="id" is
//   that element alone, merged in its place. The page's styles are replaced (or a part's added), its title set.
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

  function styles(from, part) {
    var next = from.head.querySelector("style");
    if (!next) return;
    var key = part ? 'style[data-part="' + part + '"]' : "style:not([data-part])";
    var mine = document.head.querySelector(key);
    if (!mine) {
      mine = document.createElement("style");
      if (part) mine.setAttribute("data-part", part);
      document.head.appendChild(mine);
    }
    mine.textContent = next.textContent;
  }

  // a field the person changed and has not sent: kept as they left it when the page is merged
  function changed(el) {
    if (el.nodeType !== 1) return false;
    if (el.tagName === "TEXTAREA") return el.value !== el.defaultValue;
    if (el.tagName === "SELECT") {
      return Array.prototype.some.call(el.options, function (o) { return o.selected !== o.defaultSelected; });
    }
    if (el.tagName !== "INPUT") return false;
    if (el.type === "checkbox" || el.type === "radio") return el.checked !== el.defaultChecked;
    return el.value !== el.defaultValue;
  }

  document.addEventListener("htmx:beforeSwap", function (event) {
    var d = event.detail;
    if (!d.elt || !d.elt.hasAttribute || !d.elt.hasAttribute("data-morph") || !window.Idiomorph) return;
    if (d.xhr.status >= 400 || typeof d.serverResponse !== "string") return;
    var next = new DOMParser().parseFromString(d.serverResponse, "text/html");
    var part = next.body.getAttribute("data-part");
    var sent = d.elt.closest("form");
    var how = { morphStyle: "outerHTML", ignoreActiveValue: true, callbacks: {
      beforeNodeMorphed: function (old) { return !(changed(old) && !(sent && sent.contains(old))); } } };
    d.shouldSwap = false;
    styles(next, part);
    if (part) {
      var old = document.getElementById(part), fresh = next.getElementById(part);
      if (old && fresh) Idiomorph.morph(old, fresh, how);
    } else {
      if (next.title) document.title = next.title;
      Idiomorph.morph(document.body, next.body, how);
    }
    htmx.process(document.body);
  });
})();
