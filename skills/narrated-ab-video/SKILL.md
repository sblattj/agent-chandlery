---
name: narrated-ab-video
description: "Make a narrated A/B proof video of a PR or feature: record each side's browser run with Playwright (timing marks, hooks for dynamic input like OTP codes), render title/evidence cards and A/B corner banners, voice each segment with macOS say, speed up model waits, freeze the last frame to fit the narration, and concat to one mp4. Triggers on: create a video with narration, narrated demo video, record the A/B as a video, prove it works on video, demo video for the team, screen recording with voiceover."
---

# Narrated A/B video

## More triggers

video walkthrough of the PR, make a demo recording, voiceover demo, record both stacks, explainer video, no drawtext filter, Playwright recordVideo, headless shell missing

One mp4 per claim set: title card, A clip, B clip, evidence card, verdict card, each voiced.

Built for macOS on Apple Silicon (`say`, the Playwright cache under `~/Library/Caches/ms-playwright`, `chrome-mac-arm64`). Elsewhere, set `CHROMIUM_EXE` and use `--eleven` for the voice. Needs Bun, ffmpeg and Python 3.

## Do this

```bash
S=${SKILL_DIR:-~/.claude/skills/narrated-ab-video}
$S/preflight.sh /tmp/vid                                  # chromium, playwright ffmpeg, ffmpeg, say voice
bun $S/record.ts a.json raw/a-run                         # one scenario per side (copy examples/scenario.json)
bun $S/record.ts b.json raw/b-run
bun $S/cards.ts cards.json cards                          # title/evidence/verdict PNGs + banner-A/B.png
python3 $S/build.py plan.json                             # [--voice Samantha] [--rate 182]
open -a "QuickTime Player" demo.mp4                       # opens paused; never play it yourself
```

Examples in `examples/`: `scenario.json` (steps: wait, select, click, clickIfPresent, type, send, waitStable, expand, fetchText, waitText, probeEnabled, reload; see the header of `record.ts`), `cards.json`, `plan.json`. Plan paths are relative to the plan file. Validated end to end on a 4-segment, 40s build from two real clips.

## Why it's built this way (friction mined)

- **Playwright's pinned headless shell is often not downloaded.** `record.ts` and `cards.ts` launch the newest cached `chromium-*` full build (or `$CHROMIUM_EXE`) instead of failing.
- **recordVideo needs Playwright's own ffmpeg build.** Missing means no webm. preflight reads the revision from `browsers.json` and runs `bunx playwright install ffmpeg`.
- **Homebrew ffmpeg may lack `drawtext`.** Banners are transparent PNGs from `cards.ts`, overlaid in build.py. No font or filter hunting.
- **Model replies take 10 to 60 seconds of dead air.** `send` marks "sent" and `waitStable` marks "replied". build.py plays that span at `speed` (default 10x) and the rest at 1x.
- **Narration is usually longer than the clip.** build.py holds the last frame (`tpad stop_mode=clone`) until the voice ends, so a reply stays on screen while it is explained.
- **Dynamic input (OTP codes, ids from an earlier turn):** put `{{fn:NAME}}` in a `type` step and export `NAME(page, state)` from `hooks.ts` next to the scenario. `state.lastJson` holds the last POST JSON matching `captureJsonFrom`.
- **Selectors:** buttons are matched by role and name regex (`"Tools used"`, `"^Send$"`). CSS is only for inputs and selects. Find names with a quick screenshot before scripting.
- **Concat needs identical encodes.** Every segment is re-encoded with the same codec, rate and audio layout, then joined with `-c copy`.
- **Better voice:** `ELEVENLABS_API_KEY=... build.py plan.json --eleven <voice_id>` (model eleven_multilingual_v2; clips cached by voice+text hash, so reruns spend no characters). Keep the key in a 0600 file, never in the plan, and delete it after.
- **Single-side demo (no A/B):** record one scenario, give `cards.json` one banner, and cut the same clip into several plan segments, one claim each, with `spans` speeding the waits (e.g. 5x). Same build, no A side.
- **The user may paste just `<voice_id> <key>`.** That means rebuild with `--eleven <voice_id>`. A slower voice stretches the video (72s with `say` became 92s), since build.py holds the last frame until the voice ends.
- **Re-standing a torn-down demo before filming:** short-lived auth (local JWTs, tunnel URLs, temp cloud resources) is usually dead by the next day. Re-verify with one API run before you record; a 401 "JWT token expired" there would have filmed a turn whose results never arrive.
- **Lost raw clip:** cut that side's footage from an earlier output mp4 (find its span by sampling the banner corner color), save it as `<dir>/a.webm` with `-f mp4` and an empty marks.json, and use one explicit span. Drop the `banner` since it is baked in.
- **Audio:** `say -o` writes files only. Never play the video or any audio without the user's explicit OK. Open it paused and hand it over.
- **Prove before you film.** Run the A/B and assert the result (API or log) first. The video shows a proven result; it is not the test.
- **Cards must match the clip size.** build.py does not scale. Recording at `"viewport": [1440, 900]` needs `"size": [1440, 900]` in cards.json, or the concat has mixed frame sizes.
- **Async UIs need marks, not fixed waits.** `waitText` marks when a regex shows up (or `timeout:<mark>`), `probeEnabled` with `waitMs` polls a button and logs `probes[]` in marks.json, `tryMs` on type/send/click marks `skipped:<step>` instead of aborting, so a "stays disabled" side still finishes the clip.
- **Probe the same element you click.** A CSS probe (`button[aria-label=...]`) hit a different matching button than the role-name `send` and read disabled while the send went through; use `"role"` in `probeEnabled`.
- **Dev-mode overlays (query devtools, error toasts) end up in the clip.** Add `{"clickIfPresent": "^Close .* devtools$"}` after the first wait.
- **Waiting on a reply that never "stabilizes":** a live elapsed-time badge changes the body text every second. Check `marks.json` for a `replied` mark before you build.
- **Check that the proof is in visible text.** Collapsed tool cards may not expand (`expand` silently clicks nothing). Read `marks.json` `body` for the claim string. If it's missing, change the prompt or prove it on a card instead.
- **Prove parity before you film a "base fails" claim.** Once a local base failed for a reason (a flag that was on locally, off remotely) that the real environment never hits, and the narration claimed it. Match the remote's flags first, then film.
- Title card: commits tested and flags on each side. One claim per clip segment. End on a verdict card.

## Related

- `narrated-screenshot`: a single annotated still instead of a video.
- `pr-ab-evidence`: the red/green A/B method whose result this films.
