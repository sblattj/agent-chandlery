---
name: building-a-local-html-visual-explainer
description: "Explain a code or design concept grounded in real repo code: a quick text answer (snippet with file:line and commit, flow, S-T line, a hand-drawn SVG when the flow is complex) or a styled LOCAL HTML explainer page (inline SVG diagrams, ownership legend, comparison table, light + dark), linted and screenshotted. Local file only; never publish unless asked. Triggers on: what is <term>, explain <term>, how does <term> work, where is <term> defined, sketch this, sketch X vs Y, visual explainer, show me X vs Y as a diagram, explain this visually, replace the mermaid with hand-drawn svg."
---

## More triggers

sketch (old name), visualize X locally, sketch-local-html-visual-explainer (old name), explaining-a-code-concept-from-source (old name), explain-concept (old name), explain-code-concept-from-source-with-snippets-and-handdrawn-svg (old name), show me <term> in the code, ELI5 <term>, diagram how <term> flows, draw me <term>, explain this like the last one, create a styled html visual, draw me a comparison, who owns what diagram, html visual of, glossary page with examples from the repo, ownership color legend, labels are clipped, lint the svgs for overlaps, bundle these pages into one shareable html file, this is ugly make it look like this theme

# building-a-local-html-visual-explainer

`S=${CLAUDE_SKILL_DIR:-${SKILL_DIR:-~/.claude/skills/building-a-local-html-visual-explainer}}`

Two modes, same grounding. **Quick mode** for "what is X" / "explain X" / "where is X defined": a text answer, plus one `.svg` when the flow needs it. **Page mode** for "sketch X vs Y", "visualize", "styled html", or a follow-up to a quick answer.

## Quick mode

1. Bridge the prose name to code identifiers (read-only): `$S/find-concept.sh "<term>" [code_root] [docs_root] [-a codeAlias ...]`. Roots: args, else `CODE_ROOT` / `DOCS_ROOT`, else the cwd repo and its `docs/`; the user's agent instructions may name defaults. Env: `MAX`, `BRIDGE_MAX`, `INCLUDE_TESTS=1`.
2. Read the top definition file and the one call site that enforces it.
3. Answer tight: one-line definition, why it exists, the exact snippet with `path:line` and the short SHA the script printed, a 3-6 step flow naming real classes, guards (only if in code), an `S-T:` line, then a closing question offering the next step (tests, run it live, page mode).
4. Diagram only for 3+ actors, an async hop or a branch: a self-contained `.svg` with inline styles, real class names as labels, about 10 elements, same taste rules as below. Save it at `$S/sketch.sh path <slug> [topic]` with `.html` swapped for `.svg`, print the path, and keep the numbered flow in the text. Reuse diagram sources (d2, PlantUML, mermaid) already in the docs for actors and order.

## Page mode

1. Ground every claim in source (file:line); anything unchecked goes in an `Unverified:` footer.
2. `$S/sketch.sh path <slug> [topic]` picks the file: `$SKETCH_DIR/<topic>/` if set, else a gitignored repo `tmp/`, else `~/sketches/`.
3. Copy the structure and CSS tokens of `$S/reference.html` (X vs Y, ownership legend, side-by-side table, numbered "one request, both worlds" steps) or `$S/reference-code.html` (code-to-code mapping). Replace the content, keep the classes.
4. `$S/sketch.sh check <file.html>` lints, screenshots light + dark and opens it. Read both PNGs and fix overlaps before handing over the path. Env: `SKETCH_CHROME`, `SKETCH_NO_SHOT`, `SKETCH_NO_OPEN`, `SKETCH_WIDTH`, `SKETCH_HEIGHT`, `SKETCH_BANNED_RE`.

## Gotchas

- **Prose name != code name.** A doc's "retry budget" may be `maxAttempts` in code. `find-concept.sh` pulls backticked identifiers from doc lines that mention the term and keeps only code-shaped ones (generic tokens like `POST` flood results).
- **Code wins over docs.** Follow an `AUTHORITY.md` if the script flags one; it skips `_superseded/` and `~$` lock files. Quote code, not the doc's paraphrase.
- **Tool behavior (git, GitHub, a CLI) has no file:line:** prove it in a `mktemp -d` scratch repo and quote real output, every git call bounded with `</dev/null` and `perl -e 'alarm 30; exec @ARGV'`.
- **Config needs a worked example:** real default, env override, template expression and rendered output side by side; rendered text isn't running behavior. For controller-managed fields, separate configured, requested and observed values.
- **"styled html???" after a quick answer** means they wanted page mode; reuse the facts already grounded.
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

- `querying-the-codebase-memory-graph`: callers/callees beyond one call site.
- `making-a-narrated-ab-screenshot`: captions real browser captures; this skill draws diagrams.
- `serving-a-live-call-explainer-page-with-load-more-updates`: a page that grows during a live call (newest-first sections, SSE push behind a load button). Same taste rules: a goal-driven live page shipped with Chalkboard / Marker Felt / Bradley Hand and had to be switched to the system font mid-call.
