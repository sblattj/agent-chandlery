# Interactive guides and SVG exports

Use this checklist when extending a local learning page. Keep the main skill concise.

## Keep the learning model accurate

- Apply a scope correction to every surface: overview, lessons, diagrams, questions, answer explanations, hints, rehearsals and meeting cards. Removing a chapter alone can leave stale questions behind.
- Treat a newly confirmed user decision as the intended target. Mark older source wording as pending revision; do not ask the learner to decide the same thing again. Keep implementation and live verification separate.
- For beginners, trace one real example through source inputs, overrides, templates and actual output. A glossary definition alone does not show how the pieces connect. Label hypothetical examples clearly.
- Draw configuration, runtime requests and control loops with distinct arrows. Show intermediate recipes and controllers when the source uses them. Do not draw a component inside an account or cluster unless that placement is established.
- Describe 100% as assessment coverage. Identify self-reviewed exercises explicitly; passing a guide cannot guarantee real-world readiness.

## Preserve the learner's work

- Keep the existing storage key and stable question/answer IDs for wording corrections. Verify saved answers and notes survive a real reload.
- Test wrong answers, reset and completion in a separate copy with a separate storage key. Never reset the learner's page to test the guide.
- If new assessed content changes the completion denominator, explain that change. Adding a visual reference alone need not change the scoring model.

## Export diagrams that still work

- Put wide SVGs in a horizontally scrolling region. Offer enlarge/fit controls; avoid page-wide horizontal scrolling.
- An SVG copied out of HTML loses ancestor-scoped CSS and theme variables. Inline its computed colors, typography, strokes and marker properties, including `marker-start`, `marker-mid` and `marker-end`; add a background if required.
- Make arrow references local, such as `url(#arrow)`, rather than references back to the HTML file. Preserve marker IDs and the viewBox.
- Parse the exported SVG as XML and open it independently. Check arrowheads and labels as well as the embedded version in both themes.

## Browser checks that establish the claim

- Navigating only to another hash may retain the old script. Hard-reload the file and verify the new view/function exists before claiming the update is visible.
- A reload or tool session may lose the route. Verify the hash and target element; when necessary, select the route, render and inspect it in one browser evaluation.
- Verify `innerWidth` after requesting mobile emulation. A reported override is insufficient if the next call is back at desktop width. Do not claim a mobile check from a desktop result.
- If element capture returns empty data, render the same fragment in a temporary standalone wrapper with the same CSS and explicit width. Inspect that capture instead of repeating an unchanged failing call.
- Allow source hyperlinks while rejecting external assets. A self-contained page can still link to the evidence supporting its claims.
