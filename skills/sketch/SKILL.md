---
name: sketch
description: "Build a styled, self-contained LOCAL HTML visual explainer (inline SVG diagrams, ownership legend, comparison table, light + dark) grounded in real repo code, lint it, screenshot it in both themes, then open it. Local file only; never publish unless asked. Triggers on: sketch this, sketch X vs Y, visualize X locally, create a styled html visual, visual explainer, draw me a comparison, show me X vs Y as a diagram, explain this visually, who owns what diagram, replace the mermaid with hand-drawn svg."
---

## More triggers

html visual of, make a local html diagram, visualize the architecture, styled html page for me to look at, this is ugly make it look like this theme, design page with diagrams for these PRs, ownership color legend, side-by-side comparison table, one-request-both-worlds walkthrough, S-T line, eyeball the PNGs, html file that defines terms with examples from the repo, glossary page, add more hand drawn svg so i can visualize these technologies, lint the svgs for overlaps, labels are clipped, which model draws better svg, compare the two sets of figures

# sketch

One local HTML page that makes a concept click visually, usually "X vs Y" or "who owns what", with every claim traced to real code.

## Do this

1. **Ground it first.** Pull the facts from source (file:line) or earlier in the session. Mark anything you haven't checked as unverified in a footer line. Quote `--include='*.java'` in grep, because zsh globs an unquoted `*.java` and fails with "no matches found".
   For an interactive study guide, an existing learner page, or downloadable SVGs, read [interactive guide checks](references/interactive-guides.md). Keep the latest requested scope and confirmed decisions consistent across lessons, diagrams, quizzes and recap cards.
2. **Pick the path:** `${SKILL_DIR:-~/.claude/skills/sketch}/sketch.sh path <slug>`. This picks `<repo>/tmp/<slug>.html` when that path is gitignored, and `~/sketches/<slug>.html` otherwise.
   Use a descriptive underscore filename, such as `python_dependency_access_report.html`, including for Desktop copies; avoid spaces and generic `index.html` handoffs. When a report links relative logs or JSON receipts, copy them alongside it with the directory structure intact. Exclude virtual environments, credentials and unrelated agent state. Verify the copied HTML and its linked evidence exist before handing over the Desktop path.
3. **Write the page** by copying the structure and CSS tokens of `${SKILL_DIR:-~/.claude/skills/sketch}/reference.html` (a hosted vs self-hosted CI runner page). For code-to-code mapping (spec to tool, request to response, config to config), start from `reference-code.html` (a Compose service to Kubernetes objects). Both are neutral layout examples: replace their content, keep their classes. Keep the sections that fit:
   - title + lede (the one-sentence difference)
   - legend (ownership colors: `aws` class = vendor-run, `app` class = in-repo / yours, dashed = set up outside the repo, neutral = external, red = known gap)
   - one `.card` per diagram: inline SVG, a caption, an optional `.st` S-T box
   - a "Side by side" table
   - "One request, both worlds": numbered steps with owner tags
   - an "Unverified:" footer
   Rename the owner classes when the domain isn't vendor vs your app (for example vendor/us/ops).
   S-T means "simple translation": one plain-language sentence, usually an analogy, under a diagram full of jargon.
4. **Check + look:** `${SKILL_DIR:-~/.claude/skills/sketch}/sketch.sh check <file.html>`. It lints (Python 3 required), takes headless Chrome screenshots (`<file>-light.png`, `<file>-dark.png`) and opens the page. **Read both PNGs** and fix any overlaps before you tell the user it's done. Env: `SKETCH_NO_OPEN=1`, `SKETCH_NO_SHOT=1`, `SKETCH_WIDTH=1280`, `SKETCH_CHROME=<browser binary>`, `SKETCH_BANNED_RE=<regex>` (optional house-style lint, for example characters or words the user avoids).
5. Tell the user the path and what each section shows, then offer to publish it (only if they ask) or to add a section.

## Why it's built this way (friction mined)

- **Local, not published.** The user asked for "locally"; publishing is an outward action they have to request. `check` warns if the file sits in a repo without being gitignored.
- **Screenshot both themes, then Read the PNGs.** The first draft shipped without a visual check. The screenshots later caught a footer line that ran through the box border.
- **Headless Chrome follows the macOS appearance,** so a plain screenshot of the "light" theme came out dark. The script forces `--blink-settings=preferredColorScheme=1` (light) and `=0` plus `--force-dark-mode` (dark).
- **No `timeout` on macOS** (no coreutils). The script bounds Chrome with `perl -e 'alarm shift; exec @ARGV' 60 ...`.
- **SVG text doesn't wrap.** It's about 6.5px per char at 12-13px, so a 380px chip holds about 55 chars. The lint flags any `<text>` longer than 55 chars; split long lines into two `<text>` rows 16-20px apart, inside the box's bottom edge.
- **SVG collapses leading spaces**, which flattens indented code (YAML/JSON) into one column. Keep `svg text { white-space: pre; }` in the CSS.
- **Code-to-code mapping diagrams:** color the same value with the same `<tspan class="c-a|c-w|c-g">` on both sides and draw colored curves from the end of the left line to the right box edge. Start each curve about 20px past where the text ends (monospace is about 7.5px per char at 12.5px).
- **No labels on short arrows.** In a gap under 60px, an arrow label overlaps the box edges. Move the wording into the caption instead.
- **Wait for JS before the screenshot.** A plain `--screenshot` fires before scripts run, so a JS-driven page (slides, tabs) came out blank. `sketch.sh` passes `--virtual-time-budget=4000`.
- **Headless can't go narrower than 500px.** A `--window-size=390,...` shot is a 500px layout cropped to 390, so it looks overflowed when it isn't. For a phone check, read `scrollWidth` against `clientWidth` instead (evaluate `document.documentElement.scrollWidth > clientWidth` and list the elements whose right edge passes the viewport).
- **Tall pages:** the screenshot is 4200px high by default. Raise `SKETCH_HEIGHT` if the PNG cuts off the footer.
- **Theme via CSS classes, not SVG attributes:** `svg text { fill: var(--ink) }`, box classes `.b-aws/.b-app/.b-ext/.b-warn/.b-out`, and a `.head` class on the marker path so arrowheads follow the theme. Every color token lives on `:root`, and the `@media (prefers-color-scheme: dark)` block redefines them.
- **Wide diagrams:** use `svg { width:100%; min-width:820px }` inside a `.scroll { overflow-x:auto }` wrapper so the page never scrolls sideways on a phone.
- **No Mermaid, even for a published page.** A design page built with Mermaid on light plates got "this is ugly", and the user pointed at an earlier hand-SVG page instead. Hand-draw every diagram in this skill's style: caps label (`t-cap`), bold title, body lines, amber diamond gates with mono labels, a violet box for the joining step.
- **Generate repetitive SVG with a short python loop** (step x lane matrices, 14-box service grids, sequence lifelines and messages) and splice the output into the page. Hand-typing coordinates for 60+ boxes is where overlaps creep in. Put a `.halo` class (`paint-order: stroke; stroke: var(--card); stroke-width: 4px`) on labels that sit on a line.
- **Lead with a concrete example, not the mechanism.** The first stacked-PR page (commit graphs, SHAs, merge-base) got "you gotta show examples - this is too technical". The rewrite that landed: a 4-step story with realistic names (PR #1 "Add Log in", PR #2 "Add Log out"), mock GitHub "Files changed" panels before/after built from real repro diffs, then the why, then copy-paste commands. Raw SHAs and output go in a closed `<details>`.
- **Namespace card modifiers.** `.frame.bad` inherited the bold red of a `.bad` text class and made whole cards bold; use `.f-bad` / `.f-good` for containers.
- **Cropping a full-page PNG to read it:** PIL isn't installed (`ModuleNotFoundError: No module named 'PIL'`). Use `sips -c <h> <w> --cropOffset <y> 0 in.png --out cutN.png && sips -Z 1400 cutN.png`. Offsets came out wrong more than once (a `0 0` crop showed the bottom half); if a crop looks off, Read the full PNG instead (it downsizes to about 610x2000 and is legible). On a 9000px+ page the offsets were wrong every time (offset 0 showed mid-page); the fix that worked: write a diagrams-only `prev.html` (same CSS, just the SVG cards), screenshot it at 1280x4400 per theme, and Read that whole PNG.
- **Card grids overflow on long code.** A two-column `.grid { grid-template-columns: 1fr 1fr }` of term cards with `<pre>` snippets or long file paths pushed cards past the section's right edge (seen in the dark screenshot). Use `minmax(0,1fr) minmax(0,1fr)` plus `.term { min-width: 0 }` so `<pre>` scrolls inside the card.
- **Glossary pages** ("define these terms with examples from the repo"): one card per term with definition, `file:line`, real snippet, a "what changes" box and an S-T line, then one hand-drawn SVG per section showing the terms wired together in real code (request path, startup, test setup, data lifecycle). Generate the SVG boxes from a python helper (`box`, `chip`, `ar`, `curve`, `tag`) instead of hand-typing coordinates.
- **When headless Chrome isn't allowed or available:** run `SKETCH_NO_SHOT=1 sketch.sh check`, open the page in the browser your automation tool drives (CDP or similar), and screenshot one figure at a time with a selector on its `svg` (tag the figures with `data-lint="fN"` first through a script evaluation). Point `SKETCH_CHROME` at another Chromium-family binary if that is what you have.
- **SVG overlap lint in the browser: use `getBoundingClientRect()`, never `getBBox()`.** `getBBox()` returns local coordinates and ignores a parent `<g transform="translate(0,295)">`. That reported 16 false overlaps on a before/after figure whose second half sat in a translated group. Compare each `<text>`'s client rect against the other texts (flag when the overlap is over 0.3 of the smaller one; title and subtitle rows false-flag below that), against `rect`s (a partial overlap of 15 to 80% means a label crosses a box border), and against the `svg`'s own client rect (clipped). Also count `fill="#..."`/`stroke="#..."` to catch hardcoded colors that break dark mode.
- **Linting many file:// pages:** save the lint source once with `localStorage.setItem('lint', src)`, then on each page navigate plus evaluate `eval(localStorage.getItem('lint'))`. In Chromium-family browsers file:// pages usually share storage, so each page costs 2 short calls instead of re-sending the script.
- **Fanning out SVG-heavy pages to subagents: use your strongest model.** On the same 10-page spec, the stronger model drew about 1.5x the labels with zero layout defects and caught real code-level review points; the cheaper one was faster and used fewer tokens but left clipped labels and a label crossing a box. Use the cheaper model for drafts. Subagents never render their SVGs, so the orchestrator lints and screenshots after they finish.
- **Comparing two sets of pages:** regex-extract every `<svg ...viewBox...>...</svg>` from both sets into one two-column page (shared style head and `<defs>`, one `id="<page>-<i>"` per pair). Lint that page once and screenshot pairs by `#id` instead of visiting 60 figures.
- **Self-contained:** no remotely loaded assets or CDN fonts. Ordinary source-citation links are allowed; following them requires a connection. Confirm the page itself loads without external asset requests.
- **Page conventions:** an `S-T:` simple translation for the jargon, plain wording, and an `Unverified:` line for assumptions instead of hiding them. If the user has typography rules (characters or words to avoid), enforce them with `SKETCH_BANNED_RE`.

## Related

- `explain-concept`: text-first, code-grounded explanation of one term. Use sketch when they want to *see* it.
- `narrated-screenshot`: captions real browser captures. Use sketch for drawn diagrams.
- Slide decks are a different job: use a presentation tool, and reuse this skill's overflow check.
