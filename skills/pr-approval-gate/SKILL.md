---
name: pr-approval-gate
description: "What still blocks each of your open PRs from merging: approvals, the CODEOWNERS rules nobody who approved satisfies (last match wins), draft, behind, conflicts. One read-only script, any GitHub repo (default: the current one). Triggers on: check again for approvals, did they approve, who do I still need, who is the code owner, why is my PR blocked, what's blocking merge, which PRs need <person>, needs a code owner."
---

# PR approval gate

Answers "who do I still need on which PR" in one call, instead of hand-writing a `gh` jq query each time.

## Do this

```bash
G=${SKILL_DIR:-~/.claude/skills/pr-approval-gate}/pr-approval-gate.py
$G                                   # cwd repo (its origin), my open PRs
$G <repo-folder>                     # a clone folder under $PR_GATE_ROOT (default ~/dev)
$G -R owner/repo --pr <n> <m> --json # any repo, selected PRs, machine-readable
$G -R owner/repo --author <login>    # someone else's PRs
```

Per PR: `[ready|draft, stacked on X]`, merge state, `approved:`, `owner gaps: <pattern> -> a or b`, and `needs:` (mark ready, code owner, more approvals, changes requested, conflicts, behind base). `--json` is for downstream tooling (for example, drafting a reviewer nudge from the gaps). About 15s for 23 PRs. Read-only.

To answer "which PRs need person X", grep the output for their login in `owner gaps`.

## Why it's built this way (friction mined)

- **The real block is usually CODEOWNERS, not the approval count.** A repo was once reported as "needs 3 approvals"; it was a missing code owner. A PR with two approvals still shows `REVIEW_REQUIRED` when none of them owns `/runtime/...`.
- **Last matching rule wins, per file.** The catch-all `*` line only applies to files no later rule claims. A `helm/` file needs the `/helm/` owner even if a catch-all owner approved.
- **Branch protection and rulesets return 404 for non-admins** (`gh api .../protection/required_pull_request_reviews` and `.../rules/branches/<base>`), so the required count is unknowable. Rely on `reviewDecision` plus the owner gaps.
- **Approvals = APPROVED in `latestReviews`** (one latest review per person). A re-requested reviewer's old approval stops counting; a re-request quietly cost one PR an approval.
- **Stacked PRs are judged against the trunk's CODEOWNERS** and their own delta files, since that is what they'll need when they reach the trunk.
- **Drafts can't merge even with every approval.** One PR had an approval and was quietly still a draft. The script lists `mark ready` first.
- **BEHIND is not a reason to wait.** Syncing the base in doesn't dismiss approvals in repos without `dismiss_stale_reviews`; merge the base into each PR branch (plain merge, no force-push) to clear it.
- **File list caps at 100** per PR in `gh pr list --json files`; the output flags it. Use `gh api repos/O/R/pulls/N/files --paginate` for a huge PR.
- **Team owners (`@org/team`)** are listed but not resolved to members; treat a team gap as "check by hand".

## Related

- `pr-activity-since-push`: what reviewers said or did since my last push.
- `landing-stacked-prs`: landing a stack once the gate is clear.
- `resolve-pr-threads-and-conflicts-and-merge`: merging one PR once the gate is clear.
