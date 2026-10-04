---
name: Tablua
description: An embeddable agent and its own computer, set as rows on a coding sheet.
colors:
  print: "#1f56d6"
  print-deep: "#153f9f"
  wash: "#e9f0fd"
  pencil-red: "#c23a2b"
  paper: "#ffffff"
  ground: "#f6f9fe"
  grid: "#dbe6f8"
  grid-major: "#b3c9ef"
  ink: "#23272e"
  ink-2: "#4f5663"
typography:
  display:
    fontFamily: "Archivo Variable, system-ui, sans-serif"
    fontSize: "calc(var(--row) * 1.9)"
    fontWeight: 800
    lineHeight: "calc(var(--row) * 2)"
    letterSpacing: "-0.01em"
    fontVariation: "'wdth' 125"
  headline:
    fontFamily: "Archivo Variable, system-ui, sans-serif"
    fontSize: "calc(var(--row) * 1.05)"
    fontWeight: 780
    lineHeight: "calc(var(--row) * 1.5)"
    fontVariation: "'wdth' 118"
  body:
    fontFamily: "Archivo Variable, system-ui, sans-serif"
    fontSize: "max(16px, var(--fs))"
    fontWeight: 400
    lineHeight: "var(--row)"
    fontVariation: "'wdth' 100"
  entry:
    fontFamily: "Martian Mono Variable, ui-monospace, monospace"
    fontSize: "var(--fs)"
    fontWeight: 400
    lineHeight: "var(--row)"
    fontFeature: "'tnum'"
    fontVariation: "'wdth' 87.5"
  label:
    fontFamily: "Archivo Variable, system-ui, sans-serif"
    fontSize: "0.55em"
    fontWeight: 650
    lineHeight: 1.9
    letterSpacing: "0.06em"
    fontVariation: "'wdth' 112"
  wordmark:
    fontFamily: "Archivo Variable, system-ui, sans-serif"
    fontWeight: 820
    letterSpacing: "0.02em"
    fontVariation: "'wdth' 125"
rounded:
  none: "0px"
spacing:
  cell: "var(--cw)"
  row: "var(--row)"
  sheet-gap: "48px"
  page-edge: "16px"
components:
  stamp-action:
    backgroundColor: "{colors.print}"
    textColor: "{colors.paper}"
    rounded: "{rounded.none}"
    padding: "0 1.5ch"
    height: "calc(var(--row) * 1.25)"
  stamp-action-hover:
    backgroundColor: "{colors.print-deep}"
    textColor: "{colors.paper}"
  state-mark:
    textColor: "{colors.print}"
    rounded: "{rounded.none}"
    padding: "0 0.8ch"
  state-mark-fault:
    textColor: "{colors.pencil-red}"
  line-active:
    backgroundColor: "{colors.wash}"
    textColor: "{colors.ink}"
    height: "var(--row)"
  sheet:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
    padding: "0 calc(2 * var(--cw)) var(--row)"
    width: "calc(var(--w) + 4 * var(--cw))"
  sheet-tabs:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink-2}"
    height: "44px"
  sheet-tab-current:
    backgroundColor: "{colors.wash}"
    textColor: "{colors.ink}"
---

# Design System: Tablua

## Overview

**Creative North Star: "The Coding Form"**

Every surface is a printed programmer's coding sheet: a white form ruled in non-repro blue, a numbered column ruler across its top, sequence numbers down its left margin, and graphite monospace entries set one character to a cell. The agent's life is written onto it as lines. Headings are lettered large across whole rows; the form's own furniture (title block, field labels, ruler, check boxes, stamps) is the only chrome there is.

The page itself is plain: a faint blue-white ground on which white sheets sit, one per topic, each numbered "n of 5" in its title block. The graph paper lives only inside a sheet's cell area, never on the page ground. Every measurement derives from one character cell, so the grid, the type and the layout cannot drift apart. Density is high and legible, like a form filled in by a careful hand; motion is a typewriter advancing, a row being added, a stamp landing.

Colour is printed, not painted. One saturated print blue carries the form's printing (rules, labels, ruler numbers), the headline's key word, the active row and the action. Entries stay graphite. Pencil red is the checker's correction: faults, strikes, blocks.

**Key Characteristics:**
- One character cell (`--cw`) is the unit of the whole system; widths come from a column count (80 / 56 / 38).
- White sheets on a plain ground; graph cells (fine every column, heavier every tenth) only inside the sheet's cell area.
- Graphite monospace entries; Archivo, wide, for headings and form labels; Archivo, normal width, for comment prose.
- Print blue for the form and the one action; pencil red only for faults.
- Square everything. No radius anywhere.

## Colors

A two-ink print job on white: non-repro blue for the form, graphite for what is written on it, a red pencil for corrections.

### Primary
- **Print Blue** (`print`): the form's printing. Title-block and ruler rules, field labels, column numbers, table codes, keys, the headline's emphasised word, the active row's sequence number, links, the focus ring, text selection, and the filled stamp action.
- **Deep Print** (`print-deep`): hover and pressed state of the stamp action and links; the action's border.
- **Wash** (`wash`): the active row's fill, the current sheet tab, the hover fill of a toggleable gate row.

### Secondary
- **Pencil Red** (`pencil-red`): regressed and blocked state stamps, and the 2px strike through a struck gate row or a withheld move. Nothing else.

### Neutral
- **Paper** (`paper`): the sheet, the tab bar, text on the stamp action.
- **Ground** (`ground`): the page behind the sheets. Plain, never gridded.
- **Grid** (`grid`): the fine cell lines (every column, every row) inside a sheet, tab separators.
- **Grid Major** (`grid-major`): every tenth column line, the sheet's outer border, the column ruler's minor ticks, the tab bar's top rule, scrollbar thumb.
- **Graphite** (`ink`): all entries and prose.
- **Soft Graphite** (`ink-2`): sequence numbers, the BY column, comment codes, secondary column lists, footnotes, struck text.

### Named Rules
**The Two Inks Rule.** Colour lives in the form and the active row; what is written on the form stays graphite. Blue entries are reserved for codes, keys, the open moves and the focused value.

**The Red Pencil Rule.** Pencil red marks a fault or a removal (regressed, blocked, struck). It never decorates and never marks success; a success stamp is print blue.

## Typography

**Display Font:** Archivo Variable at 118-125% width (with system-ui)
**Body Font:** Archivo Variable at 100% width
**Label/Mono Font:** Martian Mono Variable at 87.5% width (with ui-monospace), tabular figures

**Character:** A condensed, even monospace written into cells, against a wide, heavy grotesque that letters the form's printed parts and headlines. The wide face is the printer; the mono is the person filling the form in.

### Hierarchy
- **Display** (800, two rows tall at 1.9 × row, 125% width, -0.01em): one claim per page, lettered across two rows, its key word in print blue. Also the closing call ("Read the source.").
- **Headline** (780, 1.05 × row, 118% width): each sheet's title, one sentence, balanced.
- **Body** (400, max(16px, --fs), one row): the lede and comment prose in the statement field, capped at 62-66ch.
- **Entry** (Martian Mono 400, --fs up to 19px, row = 1.75 × --fs): every line on the form. Keys at 650, table codes at 700.
- **Label** (Archivo 650, 0.55em, 0.05-0.06em tracking, uppercase, 112% width, print blue): the title block's field labels (Program, Purpose, Sheet) and the ruler's field names (Seq, T, Statement, By). These are the printed form, not section kickers.
- **Wordmark** (Archivo 820, 125% width, 0.02em): TABLUA in the Program field.

### Named Rules
**The Row Rule.** Every line height is a whole or half multiple of `--row`; headings occupy whole rows so the text never leaves the ruled lines.

**The Measured Cell Rule.** `--cw` is Martian Mono's measured advance (`--chr`, measured at font load) times `--fs`; never hard-code a character width.

## Layout

The spatial model is the coding form's four fields, in character cells: sequence (columns 1-5), table code (6), statement (7 to cols-8) and BY (the last 8). The sheet's writable width is `--w = --cols × --cw`; the sheet adds two cells of margin each side. `--fs` is solved from the available width (`min(1120px, 100vw - 32px)` divided by cols + 4 and by `--chr`), capped at 19px.

- **Desktop:** 80 columns. Title block is 22ch / 1fr / 14ch, or 18ch / 1fr / 9ch / auto when it carries the stamp action.
- **Tablet (≤ 900px):** 56 columns.
- **Phone (≤ 560px):** 38 columns, sheet = 100vw - 24px. The BY field and its ruler cell are dropped; the title block becomes two columns, with Purpose and the stamp each taking a full row beneath.

Sheets stack vertically, 48px apart (16px above the first), centred. Statements wrap onto the next ruled row rather than shrinking. A fixed sheet-tab bar (44px) runs along the bottom of the viewport like a spreadsheet's, so the page pads 72px at the foot.

## Elevation & Depth

Flat paper on a desk. The only shadow is the sheet's own, a hairline contact plus a soft blue-tinted fall, enough to lift the white form off the plain ground. Nothing inside a sheet is elevated; state is shown with the wash fill, never with lift.

### Shadow Vocabulary
- **Sheet on desk** (`box-shadow: 0 1px 2px rgba(23, 32, 51, 0.06), 0 12px 32px -12px rgba(31, 86, 214, 0.18)`): every sheet, and nothing else.

### Named Rules
**The One Sheet Shadow Rule.** Only a sheet casts a shadow. Buttons, stamps, tabs and rows stay flat.

## Shapes

Square and ruled. Radius is zero everywhere. Form is made of 1px rules: print blue for the title block and ruler boxes, grid-major for the sheet edge and every tenth column, grid for the fine cells. The column ruler has tick marks on every column (25% height, grid-major) and every tenth (45%, print blue), numbered 10-80. Check boxes are 1ch squares outlined in print blue, filled blue with a paper centre when on. State marks are 2px outlined boxes rotated -4deg, like a rubber stamp.

## Components

### Buttons
The stamp: a filled block of print, pressed hard.
- **Shape:** square (0px), 1px deep-print border, height 1.25 rows.
- **Primary (stamp action):** print blue fill, paper text, Archivo 760 at 118% width, uppercase, 0.06em tracking, 1.5ch horizontal padding, with an inline 16-unit arrow SVG at 1em.
- **Hover / Focus:** fill deepens to deep print over 160ms on `cubic-bezier(0.16, 1, 0.3, 1)`; pressed nudges down 1px; focus is a 2px print-blue outline at 2px offset.
- There is one action per view: in sheet 1's title block, and again at the end of the form.

### Chips (state marks)
- **Style:** inline after an entry, 2px outline in print blue (shipped) or pencil red (regressed, blocked), Archivo 820 at 125% width, uppercase, 0.12em tracking, 0.9 row tall, rotated -4deg.
- **State:** lands with a stamp motion (scale 1.6 to 1, fading in, 350ms, 500ms after its row is typed).

### Cards / Containers (the sheet)
- **Corner Style:** square (0px).
- **Background:** paper, on the plain ground.
- **Shadow Strategy:** the sheet-on-desk shadow (see Elevation).
- **Border:** 1px grid-major.
- **Internal Padding:** two cells left and right, one row at the foot.
- Each sheet opens with its title block (Program: TABLUA / a labelled field naming what the sheet covers / Sheet n of N), the field ruler, the column ruler, then its lines on the graph cells.

### Inputs / Fields (check boxes and toggle rows)
- **Style:** a 1ch print-blue square beside a mono label; the radio pair and the gate rows use it.
- **Focus:** the global 2px print-blue outline.
- **Hover:** label turns print blue; a toggleable row takes the wash fill.
- **Struck:** a removed row keeps its place, its statement struck through in 2px pencil red and set in soft graphite; its BY reads STRUCK.

### Navigation (sheet tabs)
- **Style:** a fixed bar along the bottom, paper with a grid-major top rule; tabs separated by grid rules, Archivo 600 at 13px, 112% width, each prefixed with its sheet number in 11px mono print blue.
- **States:** default soft graphite; hover graphite; current gets the wash fill, graphite text and a 3px print-blue bar on its top edge, set by which sheet is in view. The GitHub link sits at the far right in print blue.
- **Mobile:** tab names hide, numbers remain; GitHub keeps its name.

### The Line (signature component)
The atom of the system: a grid row of seq (5ch, soft graphite), code (1ch, print blue 700, centred), statement (mono, wraps on rows) and BY (8ch, uppercase at 0.85em, soft graphite). A comment line has C in the seq field and Archivo prose in the statement. The active line takes the wash fill and its sequence number turns print blue 700. New lines type in left to right, one character per step (a stepped clip-path wipe, 18ms per character), the previous lines sliding up (layout, 450ms, `cubic-bezier(0.16, 1, 0.3, 1)`); the active highlight moves down the margin with each new row. With reduced motion the finished form shows at once.

## Do's and Don'ts

### Do:
- **Do** derive every width from `--cols` and `--cw`; add a field as a number of cells, not pixels.
- **Do** set every entry in Martian Mono at 87.5% width with tabular figures, one character per cell.
- **Do** keep line heights on `--row`, with headings spanning whole rows.
- **Do** confine the graph cells to a sheet's cell area; the page ground stays plain.
- **Do** use print blue for the form's printing, the active row and the single action, and pencil red only for faults and strikes.
- **Do** label example data as an example on the sheet itself (a footnote under the cells).
- **Do** give every motion a reduced-motion state that shows the finished form.

### Don't:
- **Don't** round a corner; the form is square (0px).
- **Don't** put a shadow on anything but a sheet.
- **Don't** colour entry text beyond codes, keys, open moves and the focused value; entries stay graphite.
- **Don't** hard-code a character width or a colour hex in a component; use `--cw`, `--chr` and the colour custom properties.
- **Don't** place content off the cells: no element sits between columns or between rows.
