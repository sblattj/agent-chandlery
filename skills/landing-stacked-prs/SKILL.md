---
name: landing-stacked-prs
description: "Unwind a chain of stacked PRs (each based on the previous PR's branch) and land them into the base branch (develop/main/master) one layer at a time, without needing a CI trigger allowlist for intermediate branches. Handles GitHub native stacks via the merge-async API. Triggers on: land the stack, unwind the stacked PRs, merge the PR stack into develop, retarget the stack to main, part of a stack, merge-async, auto-merge is not supported for stacked pull requests, fold the stack into its bottom PR."
---

# Landing stacked PRs into the base branch

Use when several PRs are chained (PR N based on PR N-1's branch) and need to reach the
real base branch. The key principle: **intermediate-branch CI is not the gate. The base
branch's protection is.** So retarget each layer to the base just-in-time and let native
CI validate it. Never rely on hardcoding intermediate branch names into CI triggers.

Repo: pass `-R owner/repo` to `gh`, or run from the clone (`gh repo view --json nameWithOwner -q .nameWithOwner`
resolves it). Below, `R` is that `owner/repo`.

## Principles

- Merge order is dictated by real dependencies (content deps + files edited by more than one
  layer). Establish that order first; do not reorder to be convenient.
- Only ever merge a layer **into the base branch**, one at a time. Never merge a child into
  its old prerequisite branch.
- Before a layer's CI matters, merge current base into that layer so its diff collapses to
  only its own change and it sees everything already landed.
- The tip branch contains every layer cumulatively; one CI run on the tip (retargeted to
  base) validates the whole assembled stack. Use it as an optional pre-flight.

## Step 0: establish order and detect conflicts

Resolve the repo's real base (default branch from the git remote, e.g. `develop` or `main`; the user's agent
instructions file (AGENTS.md / CLAUDE.md) may name known bases). For each PR, probe conflicts against
the base, not against its stale stacked base (which will read CLEAN and mislead you):

```bash
git fetch origin <base> <head> --quiet
git merge-tree --write-tree origin/<base> origin/<head> | grep -iE 'CONFLICT|changed in both' || echo "clean vs base"
```

Order rule of thumb: prerequisite content before the gate that needs it (e.g. lint-cleanup
before lint-enable); when two layers edit the same file, the earlier one merges first.

## Step 1..N: per layer, in order

```bash
PR=<number>
gh pr edit $PR -R $R --base <base>     # retarget off the stacked branch
# a separate worktree for the head branch keeps your main checkout clean:
WT=../<repo>-<head>                    # any path outside your main checkout
git worktree add "$WT" <head> 2>/dev/null || true
git -C "$WT" fetch origin --quiet
git -C "$WT" merge origin/<base>       # sync base in; resolve conflicts (see below)
git -C "$WT" push
gh pr ready $PR -R $R                  # when it is the active layer
gh pr checks $PR -R $R --watch         # native CI, base=<base>
# after review approval only:
gh pr merge $PR -R $R --squash --delete-branch
# then move to the next layer (its retarget+base-sync will absorb this one)
```

## GitHub native stacks (merge-async)

A PR made with GitHub's native stack feature refuses the classic steps above:
- `gh pr edit --base`: `GraphQL: Cannot change the base branch because the pull request is part of a stack. (updatePullRequest)`
- `gh pr merge --auto`: `GraphQL: Auto-merge is not supported for stacked pull requests.`
- `gh pr merge`: `This pull request is part of a stack and must be merged using the asynchronous merge REST API.`

Use the async API, bottom PR first (GitHub retargets the next one to the base by itself, give it ~30s):

```bash
sha=$(gh pr view $PR -R $R --json headRefOid -q .headRefOid)
u=$(gh api -X PUT repos/$R/pulls/$PR/merge-async -f merge_method=squash -f sha=$sha \
      -f merge_action=direct_merge --jq '.details.uuid // .status')
gh api repos/$R/pulls/$PR/merge-async/$u --jq '.status+" "+(.details.message//"")'   # poll until not "pending"
```

- Merging a stacked PR this way also merges every open PR **below** it, so only merge the layer you mean to land.
- After each squash, the next layer is often DIRTY on files both touched (an ADR, a version list): merge base into it, resolve, push, wait for CI, then merge-async it.
- Approvals survive base syncs in repos that don't dismiss stale reviews (check `required_pull_request_reviews.dismiss_stale_reviews` in branch protection). The real gate is often CODEOWNERS approval for each touched path, not the approval count (`pr-approval-gate` lists the gaps).
- To keep every open PR current with its base between landings, run a base-sync pass: merge the base into each open PR branch and push (plain merges, no force-push).

## Folding a stack that only works as a whole

When the layers only build together (the bottom changes a version the upper layers need), land the whole stack as ONE squash of the bottom PR instead of one squash per layer.

- Mid-stack merge-async fails with `Required status check "<gate>" is failing`: the stack shares one required check, and it stays red until the bottom PR holds every layer. Squashing upward is blocked.
- Fold top down by fast-forward instead: for each child, check `git merge-base --is-ancestor origin/<parent> origin/<child>`, then `git push origin origin/<child>:refs/heads/<parent>`. GitHub marks the child PR merged. No force-push. The layer branches keep full history; only the base gets the single squash.
- Before each fold, resolve the child's open review threads; each push re-runs bots and can add new threads on the parent.
- With `delete_branch_on_merge`, squashing the layer under the folded PR retargets it to the base by itself. It then shows DIRTY (the squash rewrote that layer's history). If the base tree equals that layer's last head tree (`git rev-parse origin/<base>^{tree}` vs `<old head>^{tree}`), `git merge -s ours origin/<base>` is exact: confirm `HEAD^{tree}` did not change, then push.
- `gh pr merge --match-head-commit` needs the full 40-char SHA; a short one fails with `Could not coerce value "<sha>" to GitObjectID`.
- The folded PR's approvals were given before the fold. Say so; the upper layers were approved on their own PRs.

## Conflict resolution

- **Workflow files edited by multiple layers** (reusable build workflows, a CI orchestrator workflow):
  keep BOTH edits, do not pick a side.
- **Format-sweep collisions** (a Spotless/Prettier apply-sweep layer vs content changes on
  base): take the base's CONTENT for the conflicted file, then re-run the formatter on it
  (`mvn -pl <module> -am spotless:apply` or `pnpm fmt`). Taking the sweep side drops real
  changes; taking base without reformatting fails the format gate. Formatter runs need the
  build to resolve (some repos pull deps from a private registry that needs a cloud login first; refresh it if the build can't fetch deps).

## Safety

- Do not force-push, rewrite history, or push to protected branches.
- Follow the repo's commit-authorship conventions (some forbid AI co-author trailers).
- Pause for human review approval before every merge into the base.
- If an intermediate-branch CI allowlist PR exists (the anti-pattern this skill replaces),
  recommend closing it; if it already merged, revert the added branch names and event types.

## Related

- `opening-a-stacked-pr-sequence`: opening the stack (bases, merge order) and the per-merge-type restack fix (`stack.sh restack`).
- `pr-approval-gate`: which code owners each layer still needs.
- `resolve-pr-threads-and-conflicts-and-merge`: landing one layer once its threads and approvals are done.
