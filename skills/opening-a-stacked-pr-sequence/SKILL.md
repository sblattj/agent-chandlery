---
name: opening-a-stacked-pr-sequence
description: "Open a stack of dependent PRs in the right order (each PR's base = the branch below it, not main), merge bottom-up, and fix the child PR after the lower one merges so already-reviewed code stops reappearing. Triggers on: stacked PRs, what base should stacked PRs target, PR shows code already reviewed, squash merge broke my stacked PR, restack after merge, rebase --onto after squash, open PR on top of another PR, PR sequencing."
---

## More triggers

stack my PRs, chain of PRs, split this into stacked PRs, PR #2 shows PR #1's changes, diff shows already merged commits, retarget the next PR, which PR do I merge first, merged the top PR first by mistake, update branch fails on a stacked PR, update-branch 403, bring the stack up to date with develop, PR says BEHIND.

# Opening a stacked PR sequence

Sets up a PR stack so every PR shows only its own changes, and tells you the exact fix for the next PR after a lower one merges.

## Do this

```bash
S=${SKILL_DIR:-~/.claude/skills/opening-a-stacked-pr-sequence}/stack.sh
$S plan add-login add-logout add-settings     # prints push + gh pr create lines, each based on the one below
$S restack add-logout 123                     # after PR #123 merged: detects merge type, prints the fix
$S restack add-logout b9097d2                 # same, with the lower PR's old tip SHA
```

Read-only: it prints commands, never pushes or rebases. Run it inside the clone (repo = the cwd's `origin`). Env: `BASE` (default: origin's default branch), `REMOTE` (default `origin`). The repo's real trunk wins (`develop`, `master`, ...); the user's agent instructions file (AGENTS.md / CLAUDE.md), if it names defaults, may list known bases.

Rules the commands encode:
1. **Base each PR on the branch below it.** PR #1 targets main, PR #2 targets PR #1's branch. Based on main, PR #2's diff carries PR #1's work from day one.
2. **Turn on auto-delete once** (`gh repo edit --delete-branch-on-merge`). GitHub only retargets PR #2 to main when PR #1's branch is deleted.
3. **Merge bottom-up.** Merging PR #2 first lands it in PR #1's branch, not main: GitHub says "merged", main has none of it, and PR #1 silently grows.
4. **After the lower PR merges, fix the child before re-review.** Which fix depends on the merge button used:

| Lower PR merged with | Child diff after retarget | Fix |
|---|---|---|
| Merge commit | clean | nothing |
| Rebase and merge | shows lower PR again | `git rebase origin/main` (drops patch-identical copies) |
| Squash (multi-commit) | shows lower PR again | `git rebase --onto origin/main <oldTip> <child>` |
| any, no force-push wanted | | `git merge origin/main` (may conflict if both PRs touched the same lines) |

Then `git push --force-with-lease origin <child>` (or plain push after the merge option).

## Why it's built this way (friction mined)

- **Squash makes a new commit with the old content.** Git tracks commit IDs, not content, so the child's merge-base stays below the lower PR and its commits look new again. Verified in scratch repos: child diff went `f +2, g +1` to `g +1` after the fix.
- **Plain rebase fails for a multi-commit squash** (conflict on the first commit: the squash patch matches none of the originals). It works for rebase-merge and for a 1-commit squash, which is patch-identical. `restack` checks this with `git cherry` instead of guessing.
- **Capture the old tip before the branch is deleted.** `restack <PR#>` reads it from `gh pr view --json headRefOid` (merged PRs keep it), so a number is enough.
- **Rebase-merge leaks too.** It was once claimed it doesn't; it does (GitHub rewrites SHAs). Only the merge commit keeps them.
- **`grep -q` under `pipefail`** can SIGPIPE the producer and flip a verdict; the script captures `git cherry` output into a variable first.
- **Name the push target** (`git push --force-with-lease origin <child>`): a bare `git push` exits 128 when the branch has no upstream.
- **Testing in scratch repos:** run git with `</dev/null` and a `perl -e 'alarm N; exec @ARGV'` bound; one unbounded batch hung the shell for 2 minutes.
- **Repos with an identity rule against the merge button** (it stamps a display name you don't want): never `gh pr merge`; fast-forward locally with `git push origin <branch>:<base>`.
- **Bringing a stack up to date with the base: the "Update branch" API refuses stacked PRs.** `gh api -X PUT repos/<o>/<r>/pulls/<n>/update-branch` on a PR whose base is another PR's branch returned 403 "Updating a stacked PR's branch via this endpoint is not supported". It works only on the bottom PR (base = trunk). Fix: in each branch's worktree, merge from the bottom up (`git merge origin/<trunk>` into the bottom branch, push, then `git merge origin/<branch below>` into the next one, push, and so on). Plain merges, no force-push. Rerun each layer's tests before pushing.
- **BLOCKED is not a conflict.** After the update, `mergeStateStatus` went from BEHIND to BLOCKED. That means the branch is current and is waiting only on a required approval.
- **GitHub native stacked PRs** (public preview, July 2026, `gh stack`) reportedly retarget and rebase for you; untested here. Prefer it if the repo has it.

## Visual explainer

If you keep one, a page like `~/sketches/stacked-pr-squash-leak.html` helps: story, base-branch comparison, mock "Files changed" panels before/after, merge-button cards. Build it with `sketch` if you want it.

## Related

- `landing-stacked-prs`: landing a long stack into the base with CI per layer (merge-base-in, no force-push).
- `sketch`: the visual explainer above.
