//! The look: a page laid out as a person's browser would lay it out, by Blitz (html5ever, Stylo, Taffy, Parley).
//!
//! In, on stdin: one line `<width> <dark: 0|1> <base url>`, then the page's HTML, its CSS inside it. The host marks
//! each element it parsed with `data-mf="<n>"`.
//! Out, on stdout: a line for each marked element: `<n> -` when it is not rendered (display: none, or inside
//! something that is not), `<n> v` when it is rendered but invisible (visibility: hidden; its children may show
//! themselves), `<n> +` when it is shown with no box of its own (display: contents), or `<n> <x> <y> <w> <h>` (its
//! border box, CSS pixels, rounded); then
//! `= <elements> <unmarked> <parse ms> <resolve ms>`, where unmarked counts elements this parser built that the
//! host's did not.
//!
//! No file, directory or network is reached: the font is inside the module and nothing is fetched.
use blitz_dom::{DocumentConfig, StyleThreading, build_single_font_ctx};
use blitz_html::HtmlDocument;
use blitz_traits::shell::{ColorScheme, Viewport};
use std::io::{Read, Write};
use std::time::Instant;
use style::computed_values::visibility::T as Visibility;
use style::values::computed::Display;

static FONT: &[u8] = include_bytes!("../fonts/Inter.ttf");

fn main() {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input).expect("stdin");
    let (head, html) = input.split_once('\n').unwrap_or((input.as_str(), ""));
    let mut head = head.splitn(3, ' ');
    let width: u32 = head.next().and_then(|w| w.parse().ok()).unwrap_or(1280);
    let dark = head.next() == Some("1");
    let base = head.next().filter(|b| !b.is_empty()).map(str::to_string);

    let t0 = Instant::now();
    let mut config = DocumentConfig::default();
    let scheme = if dark { ColorScheme::Dark } else { ColorScheme::Light };
    config.viewport = Some(Viewport::new(width, 800, 1.0, scheme));
    config.style_threading = StyleThreading::Sequential;
    config.font_ctx = Some(build_single_font_ctx(FONT));
    config.base_url = base;
    let doc = HtmlDocument::from_html(html, config);
    let t1 = Instant::now();
    let mut doc = doc.into_inner();
    doc.resolve(0.0);
    let t2 = Instant::now();

    let out = std::io::stdout();
    let mut out = std::io::BufWriter::new(out.lock());
    let (mut elements, mut unmarked) = (0u32, 0u32);
    let ids: Vec<_> = doc.tree().iter().map(|(id, _)| id).collect();
    for id in ids {
        let node = doc.get_node(id).unwrap();
        let Some(el) = node.element_data() else { continue };
        elements += 1;
        let Some(mark) = el.attrs.iter().find(|a| &*a.name.local == "data-mf") else {
            unmarked += 1;
            continue;
        };
        let (rendered, visible) = match node.primary_styles() {
            Some(s) => (
                s.get_box().display != Display::None,
                s.get_inherited_box().visibility != Visibility::Hidden,
            ),
            None => (false, false),
        };
        match (rendered, visible, doc.get_client_bounding_rect(id)) {
            (false, _, _) => writeln!(out, "{} -", mark.value),
            (true, false, _) => writeln!(out, "{} v", mark.value),
            (true, true, None) => writeln!(out, "{} +", mark.value),
            (true, true, Some(r)) => writeln!(
                out,
                "{} {} {} {} {}",
                mark.value,
                r.x.round() as i64,
                r.y.round() as i64,
                r.width.round() as i64,
                r.height.round() as i64
            ),
        }
        .expect("stdout");
    }
    writeln!(
        out,
        "= {} {} {} {}",
        elements,
        unmarked,
        (t1 - t0).as_millis(),
        (t2 - t1).as_millis()
    )
    .expect("stdout");
}
