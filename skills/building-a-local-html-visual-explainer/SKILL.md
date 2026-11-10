---
name: building-a-local-html-visual-explainer
description: "Build a styled, self-contained LOCAL HTML visual explainer (inline SVG diagrams, ownership legend, comparison table, light + dark) grounded in real repo code, lint it, screenshot it in both themes, then open it. Local file only; never publish unless asked. Triggers on: sketch (old name), sketch this, sketch X vs Y, visualize X locally, create a styled html visual, visual explainer, draw me a comparison, show me X vs Y as a diagram, explain this visually, who owns what diagram, replace the mermaid with hand-drawn svg."
---

## More triggers

sketch-local-html-visual-explainer (old name), html visual of, glossary page with examples from the repo, ownership color legend, labels are clipped, lint the svgs for overlaps, bundle these pages into one shareable html file, this is ugly make it look like this theme

# building-a-local-html-visual-explainer

`S=${CLAUDE_SKILL_DIR:-${SKILL_DIR:-~/.claude/skills/building-a-local-html-visual-explainer}}`

1. Ground every claim in source (file:line); anything unchecked goes in an `Unverified:` footer.
2. `$S/sketch.sh path <slug> [topic]` picks the file: `$SKETCH_DIR/<topic>/` if set, else a gitignored repo `tmp/`, else `~/sketches/`.
3. Copy the structure and CSS tokens of `$S/reference.html` (X vs Y, ownership legend, side-by-side table, numbered "one request, both worlds" steps) or `$S/reference-code.html` (code-to-code mapping). Replace the content, keep the classes.
4. `$S/sketch.sh check <file.html>` lints, screenshots light + dark and opens it. Read both PNGs and fix overlaps before handing over the path. Env: `SKETCH_CHROME`, `SKETCH_NO_SHOT`, `SKETCH_NO_OPEN`, `SKETCH_WIDTH`, `SKETCH_HEIGHT`, `SKETCH_BANNED_RE`.

## Gotchas

- **Browser:** `sketch.sh` uses `SKETCH_CHROME`, else the first of Chromium, Vivaldi, Brave, Edge; it never picks Google Chrome on its own. None found: `SKETCH_NO_SHOT=1`, open the page in your CDP browser and screenshot one figure at a time (`selector: "figure:nth-of-type(N)"`); a `fullPage` shot can tile the first viewport.
- **Headless quirks the script already handles:** it follows the OS theme (forced per shot), no `timeout` on macOS (perl alarm), JS pages need `--virtual-time-budget`. It can't go below 500px wide, so check phones with `scrollWidth > clientWidth`, not a narrow shot.
- **cdp `emulate` color scheme resets** when that call ends; set it and screenshot in one evaluation, or say only one theme was checked.
- **SVG text doesn't wrap** (about 6.5px per char at 12-13px; the lint flags `<text>` over 55 chars) and collapses leading spaces, so keep `svg text { white-space: pre }`. No labels on arrows shorter than 60px.
- **Overlap lint in a browser:** `getBoundingClientRect()`, never `getBBox()` (it ignores parent transforms). Flag text-text overlap over 0.3, text crossing a rect 15-80%, text outside the svg, and hardcoded `fill="#..."` that breaks dark mode.
- **Theme via classes** (`.b-aws/.b-app/.b-ext/.b-warn`, a `.head` marker class); tokens on `:root`, redefined under `prefers-color-scheme: dark`. Namespace container modifiers (`.f-bad`, not `.bad`).
- **Layout:** wide SVGs go in `.scroll { overflow-x:auto }` with `min-width:820px`; card grids use `minmax(0,1fr)` plus `min-width:0` so `<pre>` scrolls inside the card. Generate repetitive SVG (grids, lifelines) with a python loop, not hand-typed coordinates.
- **Cropping PNGs:** no PIL; use `sips -c <h> <w> --cropOffset <y> 0`. Offsets go wrong on 9000px+ pages; screenshot a diagrams-only copy instead.
- **Self-contained:** no remote assets or CDN fonts (citation links are fine). For one shareable file, inline every asset, namespace IDs and fix `url(#...)`/`href` refs, then open a copy offline.
- **Exporting an SVG** out of the page: inline computed colors and marker properties, keep marker ids local (`url(#arrow)`) and the viewBox, then parse it as XML and open it alone in both themes.
- **Subagents drawing SVG:** use the strongest model; cheaper ones leave clipped labels. They never render, so you lint and screenshot after.

## Taste (from user feedback)

- Hand-draw every diagram; no Mermaid ("this is ugly"). Hand-drawn feel comes from strokes only (an `feTurbulence` filter on boxes, never on text); never handwritten fonts (Comic Sans, Chalkboard, Marker Felt: "looks amateur"). Grep cloned pages for them.
- Lead with a concrete example (realistic names, mock before/after panels), then the mechanism; raw SHAs and output go in a closed `<details>`.
- An `S-T:` plain-language line under jargon-heavy diagrams; enforce the user's banned words with `SKETCH_BANNED_RE`.
- Local only; publishing needs an explicit ask.

## Related

- `explaining-a-code-concept-from-source`: text-first explanation of one term.
- `making-a-narrated-ab-screenshot`: captions real browser captures; this skill draws diagrams.
