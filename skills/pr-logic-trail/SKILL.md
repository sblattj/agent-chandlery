---
name: pr-logic-trail
description: "Build a logic-only walkthrough of a GitHub PR as one HTML page: drops test files, orders the production diff by the path a request travels (UI, service, downstream), and tags every hunk as changes live targets, feature path only, or plumbing. Triggers on: walk me through the logic of this PR, explain the production changes, show me the logic changes, tests vs logic, demo what this PR changes, a non-file-order PR tour, which changes in this PR hit production."
---

# pr-logic-trail

GitHub shows a PR file by file, alphabetically, tests mixed in. This shows only production code, in call order, with the impact of each change tagged.

## Do this

1. **Prep** (read-only; needs `gh` auth for the repo):
   ```bash
   ${SKILL_DIR:-~/.claude/skills/pr-logic-trail}/scripts/trail.py prep <pr> --repo <owner/name> --out <out-dir>/pr-<n>-trail
   ```
   Writes `logic.diff`, `hunks.md` (every logic hunk as `file [idx] +a -r header`, plus the excluded test files) and a `stops.json` skeleton. `--force` overwrites an edited `stops.json`.
2. **Read the logic diff** (`logic.diff`) in full. Before tagging anything shared, check the PR head for who else calls it (fetch `pull/<n>/head`, then grep or the `codebase-memory` graph). A change pitched as feature-only once turned out to hit production because the helper it touched was also called by the main build path.
3. **Fill `stops.json`**:
   - `stops`: one per hop in the request path (contract, UI, service, downstream...). Number them only because they really are a sequence.
   - `items`: `{file, hunks:[idx], impact, title, note, fold}`. Every hunk must be assigned exactly once.
   - `impact` is one of:
     - `prod`: changes behavior of live or already-shipped paths.
     - `feature`: runs only in the new or changed feature path.
     - `plumb`: imports, docs, pass-through wiring. Plumbing gets `fold: true`.
   - `labels.feature`: rename it to the feature's own word ("Playground only"). Never use "test path", because readers confuse it with test files.
   - `note`: before vs after in plain words, and why. Code wins over the PR body.
   - `live` (optional, use it when any `prod` exists): `{title, nav, note, rows:[[case, before, after]], st}`, a base vs PR table for the live impact. The note and rows accept inline HTML (`<code>`).
4. **Render**:
   ```bash
   ${SKILL_DIR:-~/.claude/skills/pr-logic-trail}/scripts/trail.py render <dir> --out <out-dir>/pr-<n>-logic-trail.html
   ```
   Render refuses on unassigned or duplicate hunks, unknown files, or a bad impact. It prints totals; quote those, don't recount by hand.
5. **Hand it over.** Give the user the local HTML path. Publish it only if they ask, through whatever page-sharing your client offers; republish to the same path to keep a stable URL. The template loads web fonts from Google Fonts and falls back to system fonts offline.

## Why it's built this way (friction mined)

- **"8 logic files but only 3 live changes?"** A reader took the file count and the change count as the same unit. The header now says "N production code + M test files", the bar says "counted per change, not per file", and a file table lists lines, changes and tags for each file. Keep all three.
- **"Test path only" was misread as test files.** The feature tag is configurable for that reason.
- **Notes legitimately contain `{{field}}`** (template syntax from the code). The placeholder check runs against the template before filling, not after.
- Test-file detection: `/test/`, `/tests/`, `__tests__/`, `.test.`, `.spec.`, `*Test.java`, `*IT.java`, `e2e-tests/`, Go/Python test names. Mention any misclassified file in the reply.
- **Sharing:** the page shows real source. If you publish it and the result says "Anyone with the link", flag that once.

## Related

- When the PR is gated by a feature flag, build a base / flag-off / flag-on table from the actual diff and put it in `live`.
- `explain-concept`: deeper explanation of a term a note mentions.
- `pr-ab-evidence`: proving the live-impact rows with A/B runs.
