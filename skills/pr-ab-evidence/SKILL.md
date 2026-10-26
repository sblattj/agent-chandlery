---
name: pr-ab-evidence
description: "Produce controlled A/B (red to green) proof that a bug-fix PR actually fixes the bug: hold the new regression test constant and swap only the production code between the PR base and the fix; optionally capture before/after UI screenshots. Works on any repo. Triggers on: A/B evidence, red/green proof, prove the fix, get evidence of the fix, before/after for this PR, does the test actually catch the bug, screenshot the bug and the fix."
---

# PR A/B evidence (red → green)

Goal: for a bug-fix PR, produce evidence a reviewer trusts - the SAME regression test
goes **red on the base branch** and **green on the fix**, with only the production code
changing between the two runs. Do NOT trust a tool's word (oasdiff, a passing suite) as the
proof; the proof is the held-constant test flipping.

## The invariant that makes it rigorous

**Hold the test constant; swap only the production fix.** If you change the test between
legs, you've proven nothing. The A leg and B leg must run the *identical* test file/case.

- **B leg (green):** run the PR's new regression test on the fix branch → expect PASS.
- **A leg (red):** remove ONLY the production fix, keep the same test, keep everything
  COMPILING, rerun → expect FAIL. Then restore.

## Choosing how to remove the fix for the A leg

Pick by the nature of the change (check with `git diff --name-status <base> <branch> -- <file>`):

- **Fix edits an existing file** (status `M`): `git checkout origin/<base> -- <prod file(s)>`
  keeping the test file → cleanest. (e.g. swap `order-panel.tsx` +
  `use-order-submit.ts` back to the base branch.)
- **Fix adds a new class/symbol the test references** (status `A`): a checkout-to-base
  won't compile (the test imports something that vanishes). Instead **surgically revert the
  one hunk** that wires the fix in, leaving the new type present so it still compiles - so
  the failure is an ASSERTION, not an import/compile error. Examples:
  - comment out the two `result = applySizeLimit(...)` call-sites in
    `RequestHandler.java` (the new `SizeLimitPolicy` class stays).
  - revert just the wildcard match in `resolveStatus`, component stays.

A compile error on the A leg is a WEAKER result than a real assertion failure - always
prefer keeping it compiling.

## Pick the sharpest single test

One behavioral test at the real integration seam beats many. Prefer a test that drives the
actual production path (e.g. `RequestHandler.handleBatch(...)` with an oversized payload)
over a unit test of the new class in isolation - the isolated unit test can't go red when
you disable the *wiring*. For a big multi-file PR, do NOT A/B the whole thing; find the one
test that most directly encodes the fixed behavior (often the cheapest is a frontend
component test).

## Always restore

After the A leg: `git checkout <branch> -- .` (or restore the specific files) and confirm
`git status --short` is clean. Never leave a worktree dirty; never commit the A-leg revert.

## Worktrees & parallelism

- Do each PR in its OWN worktree (e.g. a sibling dir `../<repo>-wt/<suffix>`) so legs/agents don't
  collide. If the branch is already checked out elsewhere, add detached:
  `git worktree add --detach <path> <branch-or-tip>`.
- Long-lived branches checked out in main worktrees stay put. Never A/B by mutating those.
- Fan out one subagent per PR (each owns its worktree). Give each the base branch, the
  branch, the sharp-test hypothesis, and the build gotchas below.
- **Remove the worktrees when done.** Once the CEV comment is posted (or the A/B is dropped):
  `git worktree remove --force <path>` for every leg/PR worktree you added, then `git worktree prune`
  in the main repo. With `node_modules` and `target/` each one is 0.5-3 GB; skipping this is how
  one repo's worktree dir reached ~490 worktrees / 178 GB. Keep one only if the user said they need it, and say which.

## Build gotchas (example: Maven backend + pnpm/Vitest frontend monorepo)

Backend (Maven, generated OpenAPI sources):
- Build current generated models first: `mvn -q -pl api-specs -am install -DskipTests`,
  then the module: `mvn -q -pl <module> -am install -DskipTests`.
- `-am` reactor with a `test` goal can hit **MDEP-98** on a downstream module
  ("Artifact has not been packaged yet") - install the dep chain first, then run the test
  WITHOUT `-am`: `mvn -q -pl <module> -Dtest=<TestClass> -Dsurefire.failIfNoSpecifiedTests=false test`.
- Real pass/fail counts live in the surefire **XML**
  (`target/surefire-reports/*.xml`), not the `.txt` summary - a `@Nested` container shows 0
  in the txt. Read `tests=/failures=/errors=` from the XML.
- Local `mvn spotless:apply` is NOT a trustworthy oracle here (a local
  google-java-format/config mismatch reformatted 177 files once). Don't use it to judge drift.

Frontend (pnpm + Vitest, oxlint/oxfmt, NOT prettier):
- A fresh worktree needs `pnpm install --frozen-lockfile` && `pnpm openapi` (or the repo's codegen step) before Vitest can
  resolve `@/api/generated/...` (generated clients aren't tracked).
- Run one test file: `pnpm exec vitest run "<path>"`. Typecheck `pnpm tc`; format check
  `pnpm exec oxfmt --check`; lint `pnpm exec oxlint`.
- `pnpm install` can scribble a stray `allowBuilds:` block into `pnpm-workspace.yaml` -
  revert it (`git checkout -- pnpm-workspace.yaml`) if it appears.

## Report format

Per PR, a compact table + the key failing assertion:

| PR | Sharp seam (held constant) | A · base (no fix) | B · fix | Bug the A leg exposes |

Include the exact command(s) and, for the A leg, the 1–5 line diff you applied. This is the
body to post as a PR comment (`gh pr comment <n> --body-file <file>`).

## Optional: before/after UI screenshots (UI PRs only)

For PRs whose fix is visible in the UI (badge/label/transcript changes), capture real
before/after images with a throwaway Vite + Playwright harness - see
[screenshots.md](screenshots.md) for the full harness recipe. Backend-only PRs get no
screenshot; say so rather than forcing one.

## Attaching evidence to the PR

- Text/table evidence → `gh pr comment <n> --body-file <file>`.
- Images: `gh` can't attach them, and raw repo URLs don't render on a private repo. Upload them
  through a logged-in browser's comment box (a CDP browser driver's `upload_file`), read the
  `user-attachments` URLs back, then post with `gh` or PATCH the existing CEV comment, and check
  that each image's `naturalWidth` is above 0. Step-by-step recipe: [screenshots.md](screenshots.md). Never
  publish internal UI to a public gist without asking.

## Approving someone else's PR

- **If the repo's CI runs only scans (no tests), run red/green yourself before approving:** the PR's test file against base
  code must fail, the full test file at the PR head must pass.
- **Check the PR body against the diff.** A body that says "no version bump" while the diff bumps the version gets flagged in the CEV.
- **Check the repo's merge settings** (`gh api repos/<owner>/<repo> --jq '{allow_squash_merge,allow_merge_commit,allow_rebase_merge}'`).
  A `mergeStateStatus: UNSTABLE` from a `NEUTRAL` scan still merges. On a squash-only repo, close the linked issue through the squash body:
  `gh pr merge <N> --squash --subject "<title> (#<N>)" --body "Fixes #<issue>"` (only on repos where the user's merge rules allow `gh pr merge`).
- When the PR doesn't link an issue, check `closingIssuesReferences` first, then open one and reference it from the CEV
  comment so the merge closes it.
- If part of a claim can't be tested in this environment (e.g. IDE-only behavior), post it as **not proven** with the
  reason, then post a follow-up CEV comment once it's proven. Don't fold it into "proven".

## Related

- `narrated-ab-video` - film the proven A/B as a narrated mp4 when the claim is visual.

