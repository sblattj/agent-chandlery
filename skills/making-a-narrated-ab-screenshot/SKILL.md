---
name: making-a-narrated-ab-screenshot
description: "Make a narrated, self-explaining screenshot: capture real browser elements over CDP (an API explorer response, a chat UI reply, a request body), lay them out A|B side by side with captions (what to look at, plain meaning of status codes, verdict, a plain-words line), and save one PNG for the user to verify yes/no. Triggers on: narrated screenshot, add narration to the screenshot, caption the screenshot, annotate screenshot for demo, A vs B side by side image, burn in captions, demo slide from screenshots, make it self-explanatory."
---

# Narrated screenshot (A|B + captions)

## More triggers

narrated-screenshot (old name), take the screenshot for me, explain what I'm looking at in the image, before/after image for the PR, evidence image

One PNG per claim that explains itself: header (claim), step 1 (what was sent to both), A column,
B column (each with a yellow "Look for" caption), green verdict, and a one-line plain-words translation.

## Do this

1. Capture each side's raw elements over CDP (`take_screenshot {selector, savePath}`), decluttered first with `evaluate_script` (Swagger UI: hide the `Response headers` / `Request duration` h5 plus its next sibling and `.download-contents`; capture `.live-responses-table` and `#operations-<Tag>-<op> textarea.body-param__text`).
2. `N=${CLAUDE_SKILL_DIR:-${SKILL_DIR:-~/.claude/skills/making-a-narrated-ab-screenshot}}/narr.sh; $N new <workdir> <name>`, then fill every `{{...}}` in `<name>.html` (images are relative to workdir).
3. Open it in a tab labeled `narr`, read `document.getElementById('shot').offsetHeight` and `devicePixelRatio`, and capture selector `#shot`. Crop with `$N crop <in.png> <out.png> 1800 <height>` only in the glitch case below. Read the PNG before showing it, then `open` it in Preview.

## Why it's built this way (friction mined)

- ALWAYS `select_page` the tab before driving it (and before switching sides) so the user watches
  it happen in the foreground instead of hunting for the tab. Users ask for this explicitly.
- No PIL / ImageMagick needed. The browser is the compositor; a 10-line Swift cropper
  (`crop.swift`, compiled on first use by `narr.sh crop`, needs Xcode command line tools) does the pixel cut.
- Some Chromium-based browsers capture `#shot` INTERMITTENTLY wrong: sometimes a correct 2x image
  (3600 x 2*offsetHeight, use as-is), sometimes a 2x-sized frame with content at 1x in the top-left and
  the rest blank. Always read the raw capture. devicePixelRatio can change mid-session (seen 2 then 1.5),
  so the expected size is `1800*dpr x offsetHeight*dpr` (read both via evaluate_script); crop
  (`narr.sh crop ... 1800 <h>`) only in the glitch case.
- `renderWidth` needs `renderHeight` too, and after the tab is foregrounded a render-size capture
  came back 7200x4000 and tiny. Don't use render sizes; use selector `#shot`.
- `sips -c --cropOffset 0 0` does NOT crop from the top-left (it cropped the right half).
  Use the Swift cropper.
- Headless Chrome `--screenshot` hung for 60s+ (killed, exit 144). Don't go there.
- `body` stretches to the window; always wrap content in `<main id="shot">` (fixed 1800px).
- Swagger inputs: `fill` with selector `#operations-<Tag>-<op> input[placeholder="<param>"]`;
  setting `.value` via JS is ignored (Swagger sends its example id, and you get a 404).
- Chat UIs: tag the smallest `main div` containing the prompt and reply as `#abchat`,
  hide any duplicate raw `json` code block, scroll its scroller to the bottom, capture `#abchat`.
- Squashed JSON strings (a message `content.text` field): add a `.dec` pre "spread out" copy with
  `.new` spans on the fields that differ.
- Request textareas capture with lots of empty space: wrap them in `.crop` with a fixed height.
- Captions must translate codes: 201 = "OK, I made it", 400 = "I refused your request". A field
  whose name collides with a generic word (e.g. `responses`) confuses readers; say
  "the field's name, think status meanings".
- Crop out tokens, secrets and customer data before the PNG leaves your machine.

## Related

- `proving-a-bugfix-pr-red-to-green`: Claim / Evidence / Verdict format; these PNGs are the Evidence images.
- `recording-a-narrated-ab-proof-video`: the same A/B as a narrated mp4 (recorded runs, cards, voiceover).
