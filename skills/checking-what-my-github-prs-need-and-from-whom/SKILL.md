---
name: checking-what-my-github-prs-need-and-from-whom
description: "What each of your open GitHub PRs needs and from whom: reviews and comments since your last push (already answered or awaiting you), CI, conflicts, draft, behind, and the CODEOWNERS rules no approver satisfies yet (last match wins). Two read-only scripts, any repo (default: the current one). Triggers on: check my open PRs, any activity since my last push, did anyone respond, did they approve, who do I still need, who is the code owner, why is my PR blocked, what's blocking merge, needs what from who, who owns the next move, which PRs need <person>."
---

## More triggers

pr-activity-since-push, pr-approval-gate, checking-my-github-prs-for-activity-since-push, checking-what-blocks-my-github-prs-from-merging (old names), new reviews on my PRs, what's each PR waiting on, needs a code owner.

# What my GitHub PRs need, and from whom

## Do this

```bash
D=${CLAUDE_SKILL_DIR:-${SKILL_DIR:-~/.claude/skills/checking-what-my-github-prs-need-and-from-whom}}
$D/pr-activity.sh [owner/repo]                     # activity since your last push + CI + conflicts (non-draft PRs)
python3 -I $D/pr-approval-gate.py [-R owner/repo]  # approvals, CODEOWNERS gaps, draft, behind (all open PRs)
```

- `pr-activity.sh`: repo is the arg, else the cwd repo, else `PR_ACTIVITY_REPO`. `AUTHOR=<login>` for someone else's PRs, `SINCE=<ISO8601>` to move the anchor. Needs bash 4+ (`mapfile`), `gh`, `jq`.
- `pr-approval-gate.py`: `-R owner/repo`, or a clone folder under `$PR_GATE_ROOT` (default `~/dev`), or the cwd's origin. `--author <login>`, `--pr <n> <m>`, `--json` for tooling. PR numbers need `--pr`: `pr-approval-gate.py 1750 1806` fails (the first number is read as the repo folder). About 15s for 23 PRs.
- Both are read-only and safe to run anytime. Run both for the full picture; run one when the question is only "did anyone respond" or only "who do I still need".

## Report: "Needs what from who"

Lead with one line on what awaits the user (review items, red CI, real conflicts), then one row per PR:

| PR | Blocked on | Who | Your move |
|----|-----------|-----|-----------|

"Who" for a review block comes from the gate's `owner gaps` (the code owner who still has to approve) or the stale changes-request's reviewer. Every row states CI and conflict state: a clean review queue once hid a red build. Group `owner gaps` by login to find who unblocks the most PRs (one catch-all owner once cleared 8 of 11).

- Stale changes-request: ask that reviewer to re-review, but first confirm you actually answered their ask (`/issues/N/comments`), not just pushed later.
- `APPROVED` but `BLOCKED`: usually path-filtered required checks that reported `skipping`, so branch protection never saw them pass. Who: a repo admin / CI owner; your move: none. Confirm with `gh pr checks <N>`.
- CI RED or a real conflict (`CONFLICTING` / `DIRTY`): awaits you. Name the failing context; an aggregate gate failing is usually a cascade from an earlier build, so name that too.

### Item tags (pr-activity.sh)

| Tag | Meaning |
|-----|---------|
| `AWAITING-YOU` | Nothing from you after this item: no comment, no review reply, no push. |
| `you-responded <ts>` | You commented / reviewed / pushed after it. |
| `you-responded in-thread <ts>` | Inline comment, and you replied inside that thread. |
| `you-responded elsewhere <ts>` | Inline comment; you responded on the PR but not in that thread. Worth a look. |
| `fyi, no reply needed` | A body-less APPROVED (or DISMISSED). |
| `~ stale changes-request: X at <ts>; you responded <ts>` | X's standing CHANGES_REQUESTED you already answered; X hasn't re-reviewed, so `reviewDecision` is stuck on it. |

"Responded" means any comment, review or commit of yours strictly after the item; it proves you spoke after them, not that you answered. Pull the bodies when that matters:

```bash
gh api repos/<owner>/<repo>/pulls/<N>/reviews  --jq '.[] | select(.state!="COMMENTED") | {user:.user.login,state,submitted_at,body}'
gh api repos/<owner>/<repo>/pulls/<N>/comments --paginate --slurp | jq '[.[][] | {user:.user.login,path,line,body,created_at}]'
```

## Why it's built this way (friction mined)

- **Don't trust `latestReviews`.** `gh pr view/list --json latestReviews` once returned only the APPROVED review and silently dropped another reviewer's standing CHANGES_REQUESTED. Both scripts derive each person's latest APPROVED / CHANGES_REQUESTED from the full REST `/pulls/N/reviews` list.
- **Three endpoints, or you miss activity:** `/pulls/N/reviews`, `/pulls/N/comments` (inline), `/issues/N/comments` (conversation).
- **`gh api --paginate --jq` filters per page.** Fine for emitting matches, wrong for counts or first-match. gh rejects `--slurp` with `--jq`, so slurp raw pages and pipe to an external `jq '[.[][] | ...]'`. This once swallowed an approval.
- **The anchor is the latest commit's `committedDate`** (REST has no push time). A review can only land after the push, so it's a safe lower bound.
- **Exclude your own login** from activity, but keep your posts as the evidence for `you-responded`.
- **Never re-request a review to check status.** `gh pr edit --add-reviewer` resets that reviewer's standing approval; a re-request once quietly cost a PR an approval.
- **The real block is usually CODEOWNERS, not the approval count.** A PR with two approvals still shows `REVIEW_REQUIRED` when none of them owns `/runtime/...`. Likewise `REVIEW_REQUIRED` with 1 approval in a 2-approval repo means "needs a 2nd", not "awaits you".
- **Last matching CODEOWNERS rule wins, per file.** The catch-all `*` covers only files no later rule claims; a `helm/` file needs the `/helm/` owner even if a catch-all owner approved.
- **Branch protection and rulesets are 404 for non-admins**, so the required count is unknowable. Rely on `reviewDecision` plus owner gaps.
- **Stacked PRs are judged against the trunk's CODEOWNERS**, since that's what they need when they reach it. PRs into another long-lived base are judged against that base's file.
- **Drafts can't merge with every approval.** The gate lists `mark ready` first.
- **BEHIND is not a conflict and not a reason to wait.** Merging the base in (plain merge, no force-push) doesn't dismiss approvals unless the repo sets `dismiss_stale_reviews`.
- **`gh pr list --json files` caps at 100 files**; the gate flags it. Use `gh api repos/O/R/pulls/N/files --paginate` for a huge PR.
- **Team owners (`@org/team`)** aren't resolved to members; treat a team gap as "check by hand".
- **ISO-8601 `...Z` timestamps compare lexicographically**, so jq string `>` is a correct time comparison.

## Related

- `rereviewing-a-github-pr-after-reply`: the reviewer side (did the author's reply or push fix what I asked?).
- `landing-stacked-github-prs`, `landing-an-approved-github-pr-blocked-by-threads`: once the gate is clear.
