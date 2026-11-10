---
name: proving-a-bugfix-pr-red-to-green
description: "Produce controlled A/B (red to green) proof that a bug-fix PR actually fixes the bug: hold the new regression test constant and swap only the production code between the PR base and the fix; optionally capture before/after UI screenshots. Works on any repo. Triggers on: A/B evidence, red/green proof, prove the fix, get evidence of the fix, before/after for this PR, does the test actually catch the bug, screenshot the bug and the fix."
---

## More triggers

pr-ab-evidence (old name)

# PR A/B evidence (red → green)

## The core

- **B leg:** run the PR's regression test on the fix branch, expect PASS.
- **A leg:** same test file, only the production fix removed, expect FAIL on an assertion (a compile error is weaker proof).
- Fix edits a file (`git diff --name-status <base> <branch>` says `M`): `git checkout origin/<base> -- <prod file>`. Fix adds a type the test imports (`A`): revert only the hunk that wires it in, so it still compiles.
- Restore after the A leg (`git status --short` clean) and never commit the revert. Report each leg's command and the 1-5 line A-leg diff.

## Build gotchas (Maven backend + pnpm/Vitest frontend)

- `-am` with a `test` goal can hit **MDEP-98** ("Artifact has not been packaged yet"): install the dep chain first (`mvn -q -pl <module> -am install -DskipTests`, generated API specs before that), then run the test WITHOUT `-am`: `mvn -q -pl <module> -Dtest=<Class> -Dsurefire.failIfNoSpecifiedTests=false test`.
- Real counts live in `target/surefire-reports/*.xml` (`tests=/failures=/errors=`); a `@Nested` container shows 0 in the `.txt`.
- Local `mvn spotless:apply` is not a trustworthy oracle: a local formatter/config mismatch once reformatted 177 files.
- A fresh worktree needs `pnpm install --frozen-lockfile` plus the repo's codegen (`pnpm openapi`) before Vitest resolves generated clients. One file: `pnpm exec vitest run "<path>"`.
- `pnpm install` can scribble a stray `allowBuilds:` block into `pnpm-workspace.yaml`; revert it.

## Remove the worktrees when done

Once the CEV is posted (or the A/B dropped), `git worktree remove --force <path>` for every leg/PR worktree, then `git worktree prune`. Each one is 0.5-3 GB with `node_modules` and `target/`; skipping this is how one repo's worktree dir reached ~490 worktrees / 178 GB.

## UI screenshots and attaching images

- **UI before/after:** mount just the changed component in a throwaway Vite page and screenshot it with Playwright, once with the fix and once with the production code reverted (same rule as the A leg). Import the app's global CSS (`grep -n "\.css" src/main.tsx`) or badges render unstyled. Copy the `VITE_*` vars from the `dev` script or it fails at import. If the component fetches a bearer token first, a `window.fetch` stub never gets reached: seed react-query with `setQueryData(<exact query key>, DATA)`. Backend-only PRs get no screenshot; say so.
- **Attaching images:** `gh` can't attach them, and raw repo URLs don't render on a private repo. In a logged-in browser over CDP, type the caption into the PR's main comment box and `upload_file` the PNG into that box's own file input (not an inline review-reply form's). Poll the textarea until it has a `user-attachments` URL and no "Uploading", then submit. Check each image's `naturalWidth` is above 0. Never put internal UI in a public gist without asking.

## Not proven is a valid verdict

If part of a claim can't be tested here (e.g. IDE-only behavior), post it as **not proven** with the reason, then a follow-up CEV once it is. Don't fold it into "proven". When the repo's CI runs only scans, run red/green yourself before approving someone else's PR.

## Related

- `recording-a-narrated-ab-proof-video` - film the proven A/B as a narrated mp4 when the claim is visual.
