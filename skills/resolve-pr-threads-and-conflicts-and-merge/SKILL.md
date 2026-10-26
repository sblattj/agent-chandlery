---
name: resolve-pr-threads-and-conflicts-and-merge
description: "Land an approved GitHub PR end to end: reply to and resolve every open review thread, update or fix a stale or conflicting branch, then merge (auto-merge if blocked) and wait until MERGED. Triggers on: merge this PR, resolve the threads and merge, base branch policy prohibits the merge, BLOCKED with approvals, conversation resolution required, BLOCKED again after update, get this PR merged, land the PR."
---

# Resolve threads, fix conflicts, merge

One script takes an approved PR from BLOCKED to MERGED. Needs `zsh`, `gh` and `jq`.

## Do this

```bash
L=${SKILL_DIR:-~/.claude/skills/resolve-pr-threads-and-conflicts-and-merge}/land.sh
$L <pr> --dry-run                                     # repo = the cwd's (gh repo view); lists threads with no reply (exit 2)
$L <pr> -R owner/repo --dry-run                       # any other repo
$L <pr> -R owner/repo --replies replies.json          # post replies, resolve, update branch, merge, wait (default 600s)
```

`replies.json` is `[{"cid":"<thread's first comment databaseId>","body":"markdown"}]`. The dry run prints each thread URL; the id is the number after `discussion_r`. Log: `/tmp/land-pr/<repo>-<pr>.log` (override with `LOG=`).

Exit codes:
- 0: merged
- 2: threads still need a reply
- 3: conflicts
- 4: not merged within `--wait`
- 5: draft, closed or bad arguments

What the script does:
1. **Conflicting (exit 3):** stops. Merge the base into the branch in a worktree (never rebase a shared branch), resolve, run the module's tests, push, rerun.
2. **BEHIND:** runs `gh pr update-branch`.
3. **Threads:** posts each reply and resolves the thread. It also resolves a thread whose last comment is already yours. For any other thread it stops with exit 2. Draft a reply per thread (what changed, with the commit link, or the reason it's a follow-up), get the user's OK on the text if they haven't seen it, then rerun with `--replies`.
4. **Merge:** tries a direct merge with the repo's allowed method (it reads `allow_squash_merge`, then merge, then rebase). If refused, it arms `--auto` and polls. On timeout it prints the failing and pending checks plus `reviewDecision`.

## Why it's built this way (friction mined)

- **Approvals plus green CI can still be BLOCKED.** A branch rule with `requiresConversationResolution` blocks the merge while any thread is open. `gh pr merge` then says only "base branch policy prohibits the merge". Read the rule with GraphQL `refUpdateRule` (required approvals, code owners, conversation resolution, required checks).
- **Reply before resolving.** A resolved thread with no answer reads as a brush-off. Reword any reply that ends in a question ("OK with that?") into a statement before you resolve, or leave that thread open.
- **Replies go to `pulls/<pr>/comments/<first comment id>/replies`**, and resolving uses the `resolveReviewThread` mutation with the `PRRT_...` node id. `gh pr comment` posts to the PR conversation, not the thread.
- **Arm auto-merge first** when only thread resolution is pending. It merges the moment the last thread closes: within about a minute of the last resolve on the first run, with no second command.
- **`gh api` has no `-R`.** Run it from the repo, or pass `repos/<owner>/<repo>/...` in the path.
- **Never re-request reviewers or @mention them** to speed things up: re-requesting resets a standing approval. Draft a chat nudge for the user instead.
- **Fast-forward the local branch before merging the base.** A worktree was 5 commits behind its remote, and merging the base into it produced a conflict that doesn't exist on the real branch. Run `git merge --ff-only origin/<branch>` first.
- **Red CI after merging the base can be the base branch's fault.** A PR touching one UI test failed the bundle budget check, because an earlier PR had merged with that check red, and the base branch's own run skipped the UI job. Check the last PR touching the failing area (`gh pr view <n> --json statusCheckRollup`) before you debug your own diff. If the base is broken, fix it in its own PR, merge that, then update-branch.
- **Updating a BEHIND branch can re-block it.** Merging the base re-ran an AI review bot, which opened a fresh thread 20 minutes later:
  CI went green, then `mergeStateStatus` was BLOCKED again with 1 open thread. Recount unresolved threads after every push, not once.
- **Declining a bot finding:** start the reply with `Won't fix:` (or "by design"), then the reason. prxref-style reviewers read that
  opener as a decline and stop re-raising it; a reply like "invalid, because..." is not recognized.
- **Stacked PR refuses the merge** (`This pull request is part of a stack and must be merged using the asynchronous merge REST API`,
  REST returns 403 too): use `merge-async` from `landing-stacked-prs`; it returned 202, then `merged` within 20s.
- **Polling needs retries.** One `Post .../graphql: EOF` killed a 40-minute wait; `land.sh` now retries transient gh errors.
- Repos with an identity rule against the merge button (it stamps a display name): don't use this script there. Fast-forward with `git push origin <branch>:<base>`.

## Related

- `pr-approval-gate`: who still has to approve (CODEOWNERS gaps) before this can merge.
- `opening-a-stacked-pr-sequence`, `landing-stacked-prs`: after a lower stacked PR lands, restack the next one, then run this.
- `pr-activity-since-push`: which threads still await your reply.
