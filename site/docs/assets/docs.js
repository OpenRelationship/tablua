// docs.tablua.com, on top of pages that read without it: search (press /), copy buttons on code, the phone menu,
// and the contents column following the reader.
(function () {
  // the phone menu
  var menu = document.querySelector(".menu");
  if (menu) {
    menu.addEventListener("click", function () {
      var open = document.body.classList.toggle("menu-open");
      menu.setAttribute("aria-expanded", String(open));
      menu.setAttribute("aria-label", open ? "Close the list of pages" : "Open the list of pages");
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && document.body.classList.contains("menu-open")) menu.click();
    });
  }

  // copy buttons
  document.querySelectorAll(".code").forEach(function (box) {
    var b = document.createElement("button");
    b.type = "button";
    b.className = "copy";
    b.textContent = "Copy";
    b.addEventListener("click", function () {
      navigator.clipboard.writeText(box.querySelector("code").textContent).then(function () {
        b.textContent = "Copied";
        setTimeout(function () { b.textContent = "Copy"; }, 1400);
      });
    });
    box.appendChild(b);
  });

  // the contents column marks the heading being read
  var links = Array.prototype.slice.call(document.querySelectorAll(".toc a"));
  if (links.length && "IntersectionObserver" in window) {
    var byId = {};
    links.forEach(function (a) { byId[a.getAttribute("href").slice(1)] = a; });
    var seen = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        links.forEach(function (a) { a.classList.remove("on"); });
        var a = byId[en.target.id];
        if (a) a.classList.add("on");
      });
    }, { rootMargin: "-70px 0px -70% 0px" });
    Object.keys(byId).forEach(function (id) { var h = document.getElementById(id); if (h) seen.observe(h); });
  }

  // search over every page's title, headings and text, loaded on first use
  var q = document.getElementById("q");
  var list = document.getElementById("results");
  if (!q || !list) return;
  var index = null, picked = -1, found = [];
  function load() {
    if (index) return Promise.resolve(index);
    return fetch("/search.json").then(function (r) { return r.json(); }).then(function (d) { index = d; return d; });
  }
  function esc(s) { return s.replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function mark(s, words) {
    var out = esc(s);
    words.forEach(function (w) { out = out.replace(new RegExp("(" + w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "ig"), "<mark>$1</mark>"); });
    return out;
  }
  function snippet(text, words) {
    var low = text.toLowerCase(), at = -1;
    for (var i = 0; i < words.length && at < 0; i++) at = low.indexOf(words[i]);
    if (at < 0) return "";
    var from = Math.max(0, at - 40);
    return (from > 0 ? "…" : "") + text.slice(from, at + 80) + "…";
  }
  function search(term) {
    var words = term.toLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length) return [];
    return index.map(function (p) {
      var score = 0, t = p.t.toLowerCase(), h = p.h.join(" ").toLowerCase(), x = p.x.toLowerCase();
      for (var i = 0; i < words.length; i++) {
        var w = words[i], s = 0;
        if (t.indexOf(w) >= 0) s += 10;
        if (h.indexOf(w) >= 0) s += 4;
        if (x.indexOf(w) >= 0) s += 1;
        if (!s) return null;
        score += s;
      }
      return { p: p, score: score, words: words };
    }).filter(Boolean).sort(function (a, b) { return b.score - a.score; }).slice(0, 8);
  }
  function show() {
    var term = q.value.trim();
    if (!term) { list.hidden = true; return; }
    load().then(function () {
      found = search(term);
      picked = found.length ? 0 : -1;
      list.innerHTML = found.length
        ? found.map(function (r, i) {
            var snip = snippet(r.p.x, r.words);
            return '<li role="option" aria-selected="' + (i === 0) + '"><a href="' + r.p.u + '">' + mark(r.p.t, r.words) +
              "<small>" + esc(r.p.s) + (snip ? " · " + mark(snip, r.words) : "") + "</small></a></li>";
          }).join("")
        : '<li class="none">Nothing matches “' + esc(term) + "”.</li>";
      list.hidden = false;
    });
  }
  function select(i) {
    var items = list.querySelectorAll("li[role=option]");
    if (!items.length) return;
    picked = (i + items.length) % items.length;
    items.forEach(function (li, k) { li.setAttribute("aria-selected", String(k === picked)); });
    items[picked].scrollIntoView({ block: "nearest" });
  }
  q.addEventListener("focus", load);
  q.addEventListener("input", show);
  q.addEventListener("keydown", function (e) {
    if (e.key === "ArrowDown") { e.preventDefault(); select(picked + 1); }
    else if (e.key === "ArrowUp") { e.preventDefault(); select(picked - 1); }
    else if (e.key === "Enter" && found[picked]) { location.href = found[picked].p.u; }
    else if (e.key === "Escape") { q.value = ""; list.hidden = true; q.blur(); }
  });
  document.addEventListener("click", function (e) { if (!e.target.closest(".search")) list.hidden = true; });
  document.addEventListener("keydown", function (e) {
    if (e.key === "/" && document.activeElement !== q && !/input|textarea/i.test(document.activeElement.tagName)) {
      e.preventDefault();
      q.focus();
    }
  });
})();
