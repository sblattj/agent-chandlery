---
name: cdp-route-snapshots
description: "ARIA-snapshot a list of routes of a running web app through the cdp-toolkit CLI in its own browser tab, then diff two runs (A vs B) for UI parity. Read-only. Triggers on: ARIA snapshot these screens, snapshot the UI A vs B, UI parity check, accessibility tree diff, Playwright connectOverCDP timed out, cdp take_snapshot truncated, Unterminated string from cdp."
---

# cdp-route-snapshots

Answers "do these screens render the same on A and B" from the accessibility tree, not pixels.

Needs the `cdp` CLI from the `cdp-toolkit` package on PATH, and a browser with its remote debugging port open.

## Do this

```bash
S=${SKILL_DIR:-~/.claude/skills/cdp-route-snapshots}/snap.py
python3 $S http://localhost:5181 out/A /overview /agents /settings --api '^/(api|service)/'
python3 $S http://localhost:5182 out/B /overview /agents /settings --api '^/(api|service)/'
python3 $S --diff out/A out/B        # per route: same / DIFF + unified diff; exit 1 on any diff
```

Run an A vs A pair first (same build twice) to see which routes are noisy before trusting an A vs B diff.

## Why it's built this way (friction mined)

- **Playwright `connectOverCDP` to the user's everyday browser timed out at 30 s** (many tabs open). The `cdp` CLI attached fine, so the helper uses it and never launches a bundled Chromium.
- **The bun `cdp` CLI cuts piped stdout at 64 KB** on exit, so big `take_snapshot` JSON came back as "Unterminated string". The helper writes stdout to a temp file instead of a pipe.
- **Own tab, always closed:** `new_page --label route-snap-<pid>`, `close_page` in `finally`, so the user's tabs are never driven. Exit 3 means the debug port is down: restart the browser with remote debugging enabled (`--remote-debugging-port`).
- **Wait for the app, not a timer:** poll `performance.getEntriesByType("resource").length` until it holds for 2.5 s (max 30 s). Request paths matching `--api` are recorded too, from any origin (a UI with a separate `VITE_API_BASE_URL`-style API origin recorded zero paths under a same-origin filter), ids normalized; CDP gives no statuses here.
- **Normalize before diffing:** `[uid]` prefixes, the per-run `localhost:<port>`, UUIDs, ISO timestamps and "N minutes ago" all differ run to run.
- **Check it really rendered:** a sign-in or error page diffs "same" on both sides. Look at the line count and the request paths for the first route before running the rest.
- `snapshot` output is JSON `{"snapshot": "..."}`; `evaluate_script` takes `{"expression": ...}` and needs an invoked IIFE for multi-statement code.

## Related

- `pr-ab-evidence` (red/green proof for a PR), `narrated-screenshot` (when the proof should be visual).
