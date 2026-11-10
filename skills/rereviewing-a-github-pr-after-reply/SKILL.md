---
name: rereviewing-a-github-pr-after-reply
description: "Re-review a GitHub PR after the author replies or pushes: list what others said and pushed since my last review, check every commit they claim fixed things is actually on the head (force-push and rebase can drop it), range-diff old vs new head, re-check their factual claims in code, then post a review that supersedes my old verdict. Triggers on: re-review, look at the PR's updates, author says fixed, they addressed my comments, is the fix on the branch, did the force-push drop the commit, flip my request changes, check the one I already reviewed."
---

## More triggers

pr-rereview-after-reply (old name)

# Re-review a PR after the author's reply

Answers: since my last review, what did they say, what actually changed on the head, and does my verdict still hold.
Works on any GitHub repo: the PR URL carries `owner/repo`.

## Do this

```bash
REPO_DIR=<local clone> ${CLAUDE_SKILL_DIR:-${SKILL_DIR:-~/.claude/skills/rereviewing-a-github-pr-after-reply}}/rereview-status.sh <pr-url> [my-login]
BACK=2 ...   # measure from my 2nd-to-last review (e.g. after I already posted a newer one)
```

Read-only. Prints: my last review (state, commit), `old...head` compare status, every comment / inline reply / review /
force-push by others since then, each commit SHA named in their replies marked `ON HEAD` or `NOT ON HEAD`, and a
`git range-diff` of old vs new head when `REPO_DIR` is set. `my-login` defaults to the account `gh api user` returns.

Then:
1. **Any `NOT ON HEAD`**, or a range-diff with only `=` rows while they say "fixed": the fix is not on the PR. Say so with the compare status and one at-head proof (a line that still has the old code), without naming who dropped it (see below).
2. Verify each factual claim in their replies in code at the head (`git show "${H}:path"`), then post one new review at the new head that supersedes the old state (APPROVE clears my CHANGES_REQUESTED).

## Why it's built this way (friction mined)

- A reply said "the fixes are in `<sha>`", then a later force-push (a rebase onto the base, by a *different* person)
  dropped that commit. The head showed the same patches as before. Only `gh api repos/O/R/compare/<sha>...<head>`
  (`diverged`) and `range-diff` (all `=`) caught it; the PR body had been updated, so it looked addressed.
- `compare` statuses relative to head: `identical`/`ahead` mean the SHA's content is on head; `diverged`/`behind` mean it is not.
  A local `git cat-file` fails on a dropped SHA ("Not a valid object name"); the GitHub API still has it, so use the API.
- GitHub clears the review request once you review, so "PRs requesting my review" no longer lists it; find it by `reviewed-by`.
- zsh: `$H:path` trips history modifiers (`$H:a`); always `"${H}:path"`.
- Don't blame the last force-pusher. A review once tagged the person whose rebase was visible, but the commit had been
  dropped earlier by the author's own rollback; the rebase carried the branch faithfully. Report the fact, not the actor,
  and correct publicly if wrong.
- Claimed SHAs are listed from every reply since my review, including retracted ones: read the newest reply first
  ("`<sha>` is no longer the fix commit, read `<new>`") before calling a NOT ON HEAD a problem.
- A review's `commit_id` can be remapped after a rebase (an approval on one SHA later showed a different one),
  so the "my last review on" SHA may not be the one you reviewed. Trust `submitted_at` and the range-diff.
- Approvals go stale after a push: `reviewDecision` flips to `REVIEW_REQUIRED`. Re-approve on the new head; other
  approvers may need to as well (the rule may want N approvals of the latest push, and it is not readable without admin).
- **Green CI and approvals can still leave the PR unmergeable.** A head with only a comment-tweak commit came back `mergeable: CONFLICTING`. Name the conflicting files without checking anything out: `git merge-tree --write-tree --name-only origin/<base> <head-ref>` (git 2.38+; line 1 is the tree id, then the files, then `CONFLICT (modify/delete): ...` lines). A modify/delete conflict means the PR deletes a file that base kept editing (`git log --oneline origin/<base> -- <file>` shows which PRs). Put it in the risk table as a Medium with an ask to carry those edits over, not request changes.
- **Nothing new is a valid answer.** `old->head: identical` with no activity and my approval on head means there's nothing to re-review. If `reviewDecision` is still `REVIEW_REQUIRED`, other reviewers are missing (`gh pr view N --json reviews,reviewRequests`). Don't nudge them on the PR (re-requests reset standing approvals); offer the user a chat-message draft instead.

## Related

- `checking-what-my-github-prs-need-and-from-whom`: the same question from the author side (activity on my own PRs), plus which code owners still have to approve.
