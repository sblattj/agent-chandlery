---
name: pr-activity-since-push
description: "Check your open non-draft PRs for activity since your last push (reviews, inline or conversation comments by anyone else), plus CI and conflict state, and report per PR what it is blocked on and who owns the next move. Repo: an argument, default the current one. Triggers on: check my open PRs, any activity since my last push, has anyone reviewed, did anyone respond, needs what from who, who owns the next move, what's each PR blocked on, who do I need to ping."
---

## More triggers

new reviews on my PRs, what changed on my PRs, PR status check, what's each PR waiting on.

# PR activity since your last push

Answers: **"On my open non-draft PRs, has anyone done anything since I last pushed?"**
(another review, a review comment, a conversation comment.)

## Do this

```bash
A=${SKILL_DIR:-~/.claude/skills/pr-activity-since-push}/pr-activity.sh
$A                                  # current repo (gh repo view)
$A <owner>/<repo>                   # any repo
PR_ACTIVITY_REPO=<owner>/<repo> $A  # fallback when run outside a clone
AUTHOR=<login> $A <owner>/<repo>    # someone else's PRs
```

Repo resolution: the arg, else the cwd repo (`gh repo view`), else `PR_ACTIVITY_REPO`. Outside a repo with no arg, check the user's agent instructions file (AGENTS.md / CLAUDE.md), if it names a default repo; otherwise ask. Needs bash 4+ (`mapfile`), `gh` and `jq`.

It prints, per PR: the last-push time, `reviewDecision`, `mergeable/mergeStateStatus`,
the **CI rollup** (`green` / `pending(n)` / `RED <contexts>`), a **MERGE CONFLICT** flag when
the branch actually conflicts, and every review/comment by **someone other than you** after
your last commit, each tagged with whether you already dealt with it. The summary buckets PRs
into: awaiting you (reviews), CI failing, merge conflict, CI still running, stale
changes-requested. It is read-only and safe to run anytime.

## Default output: the "Needs what from who" table

**Relay it as a per-PR "Needs what from who" table**, not the raw scan. Lead with one line on whether anything awaits
the user (usually nothing), then the table, then a one-line shape-of-it summary grouping the PRs by
who owns the next move. Columns:

| PR | Blocked on | Who | Your move |
|----|-----------|-----|-----------|

Fill each row from the scan + a small detail pull, using this mapping:

- **`CHANGES_REQUESTED` with a `~ stale changes-request`** → Blocked on: that reviewer's
  standing CR (name what they asked, one clause). Who: **that reviewer** to re-review. Your
  move: ping them. Before writing "you answered," confirm you actually replied to their ask
  (pull `/issues/N/comments` + `/pulls/N/comments`), not just that the script saw a later
  push (a push alone can leave their question unanswered).
- **`REVIEW_REQUIRED` with fewer approvals than the repo requires** → Blocked on: needs
  another approval. Who: a 2nd (or Nth) codeowner. Your move: nudge for it. **If the repo
  requires 2 approvals**, 1 approval + `REVIEW_REQUIRED` = "needs a 2nd approval," it is
  not awaiting you.
- **`APPROVED` decision but `mergeStateStatus: BLOCKED`** → not a review issue. Usually the
  per-service required checks reported `skipping` (path-filtered: the PR only touches
  `.github/**` or one service, so the other required contexts never run and branch protection
  never sees them pass). Who: a repo admin / CI owner to merge or relax the required contexts.
  Your move: none. Verify with `gh pr checks <N> -R <repo>` (look for `skipping` rows) and
  `gh pr view <N> --json reviewDecision,mergeStateStatus`.
- **CI is RED (a required context FAILURE on the head commit)** → this awaits **you**, not a
  reviewer: fix the build. Name the failing context and link its run. A green review decision
  does not mean the PR can merge. The script prints `CI: RED <contexts>` and lists it under
  `CI FAILING` in the summary.
- **Real merge conflict (`mergeable: CONFLICTING`, or `mergeStateStatus: DIRTY`)** → awaits
  **you**: resolve it. `BEHIND` alone is NOT a conflict (fast-forwardable), don't report it as
  one. The script prints `MERGE CONFLICT` on the row and under `MERGE CONFLICT` in the summary.
- **quiet PR (no activity, healthy decision, green CI, no conflict)** → Blocked on: nothing new
  / needs approvals per its decision. Keep the row to one line.

Every PR's row must state conflict + CI, because a clean review queue hides a red build (this
was missed once: a PR sat review-clean while its build job and the aggregate CI gate check
were failing on its head commit). Roll CI-failing and conflicting PRs into the
opening "what awaits you" line alongside review items.

For the quiet ones a one-line "nothing since your push" in the row is enough. End with the
offer of concrete next actions (draft a chat nudge for the user to send, update BEHIND branches, dig into a
specific block) rather than stopping cold.

### Item tags (the part that matters)

| Tag | Meaning |
|-----|---------|
| `AWAITING-YOU` | Nothing from you after this item: no comment, no review reply, no push. Act on it. |
| `you-responded <ts>` | You commented / reviewed / pushed after it. Already handled. |
| `you-responded in-thread <ts>` | Inline diff comment and you replied inside that thread. |
| `you-responded elsewhere <ts>` | Inline diff comment; you responded on the PR but not in that thread. Worth a look. |
| `fyi, no reply needed` | A body-less APPROVED (or DISMISSED). Good news, nothing to do. |
| `~ stale changes-request: X at <ts>; you responded <ts>` | Reviewer X's standing CHANGES_REQUESTED that you already answered (comment or push) and they have not re-reviewed. The PR's `reviewDecision` is stuck on it. Ask X to re-review; do NOT re-request via `gh pr edit --add-reviewer`. |

The "did I respond?" check treats any of these as a response by you, strictly after the
item's timestamp: a conversation comment, an inline comment, a submitted review, or a
commit on the PR. It does not read your reply for relevance; it only proves you spoke after
they did. If the user wants to know whether the reply actually addressed the request, pull
the bodies (below) and judge.

If a PR shows new activity and the user wants detail, pull the review body + its inline
comments:

```bash
gh api repos/<owner>/<repo>/pulls/<N>/reviews  --jq '.[] | select(.state!="COMMENTED") | {user:.user.login,state,submitted_at,body}'
gh api repos/<owner>/<repo>/pulls/<N>/comments --paginate --slurp | jq '[.[][] | {user:.user.login,path,line,body,created_at}]'
```

## Why it's built this way (friction mined from real sessions)

- **Mine vs teammates.** Always `gh pr list --author @me --draft=false --state open`. A bare
  `gh pr list` returns the whole team's PRs and you'll waste a step filtering to yours.
- **The anchor is the latest commit's `committedDate`**, used as a proxy for "last push" - a
  review can only land after the push, so it's a safe lower bound. GitHub REST exposes no
  per-commit push time. Override with `SINCE=<ISO8601>` if you need a different cutoff.
- **Three separate endpoints, or you miss activity:** `/pulls/N/reviews` (reviews),
  `/pulls/N/comments` (inline diff comments), `/issues/N/comments` (conversation comments).
  Reviews and comments are different objects; checking only one under-reports.
- **`gh api --paginate --jq` applies the filter PER PAGE**, not to the whole set. For a
  FILTER that just emits matching lines that's fine - pages concatenate (this script's three
  activity queries rely on it). But an across-page AGGREGATION (first match, a count,
  `[...][0]`) is wrong per-page, and you CANNOT fix it with gh's own `--jq` + `--slurp`: gh
  errors `the --slurp option is not supported with --jq`. Slurp the raw pages and pipe to an
  EXTERNAL jq instead: `gh api … --paginate --slurp | jq '[.[][] | …]'`. (Both were real bugs
  this session - including one that silently swallowed an approval and one shipped to a CI
  workflow.)
- **Exclude your own login** (`.user.login != $ME`, from `gh api user --jq .login`). Your own
  post-push replies aren't "someone responded". But they ARE the evidence for the
  `you-responded` tag, so the script fetches each endpoint once (slurped) and filters twice:
  others-after-anchor for the activity list, mine-anywhere for the response timeline.
- **`gh pr view --json latestReviews` is not trustworthy.** On one PR it returned only the
  APPROVED review and silently dropped a standing CHANGES_REQUESTED from another reviewer,
  which hid the stale-CR case and undercounted. Derive per-author latest opinionated review
  yourself from the full REST `/pulls/N/reviews` list (`group_by(.user.login) | last`, states
  APPROVED / CHANGES_REQUESTED only). The approvals count comes from the same derivation.
- **A bare approval is not a question.** Before the awaiting/responded split, every approval
  after a push showed up as "new activity" and read like a to-do. Body-less APPROVED /
  DISMISSED reviews are tagged `fyi, no reply needed` and never count toward "awaiting you".
- **ISO-8601 `...Z` timestamps compare lexicographically = chronologically**, so a plain jq
  string `>` is a correct time comparison. No date math needed.
- **NEVER re-request a review just to check status.** `gh pr edit --add-reviewer <who>`
  RESETS that reviewer's standing approval back to pending. Checking activity is strictly
  read-only; re-request only when the user explicitly asks to nudge someone.
- **`REVIEW_REQUIRED` + 1 approval means "needs a 2nd," not "awaiting you."** When branch
  protection requires 2 approvals, a PR sitting at 1 approval with a healthy scan is
  blocked on a second codeowner, not on you. Don't file it under "awaiting you."
- **`APPROVED` but `BLOCKED` is a checks problem, not a review problem.** On one PR (2
  approvals, `reviewDecision: APPROVED`) `mergeStateStatus` was still `BLOCKED` because every
  per-service required context reported `skipping`: the PR only touched `.github/**`, so the
  path-filtered service jobs never ran and branch protection never saw its required contexts
  pass. The aggregate CI gate check was green but that isn't the only required context. That's an admin/CI merge
  action, so the row's "Who" is a repo admin and your move is none. Confirm with
  `gh pr checks <N> -R <repo>` (`skipping` rows) before saying so.
- **Confirm a stale-CR reply actually answered the ask.** The script tags `you-responded` from
  a later push/comment timestamp alone; it does not read relevance. When a reviewer asked a
  concrete question (e.g. a reviewer's repeated "what's the ticket / put it in the sprint"),
  pull `/issues/N/comments` and check you posted the answer, not just that you pushed. In past
  checks the answers were real conversation replies; verify, don't assume.

## Status columns cheat-sheet

- `reviewDecision`: `APPROVED` | `CHANGES_REQUESTED` | `REVIEW_REQUIRED` | `NONE`.
- `mergeStateStatus`: `BEHIND` = behind base, not a conflict (fast-forwardable);
  `BLOCKED` = waiting on required checks/reviews; `DIRTY`/`CONFLICTING` = real merge
  conflict; `CLEAN` = ready. `mergeable` is `MERGEABLE` | `CONFLICTING` | `UNKNOWN`.
- **CI rollup** (`statusCheckRollup`): a context is a `CheckRun` (`.name`/`.status`/
  `.conclusion`) or a `StatusContext` (`.context`/`.state`). RED = any `conclusion` in
  FAILURE/TIMED_OUT/CANCELLED/ACTION_REQUIRED (or `state` FAILURE/ERROR). `skipping` is
  path-filtered, neither fail nor pending. An aggregate gate check failing is usually a cascade off an
  earlier failed build, not an independent problem, so name the real failing build too.

## Related

- Who still has to approve (CODEOWNERS gaps): `pr-approval-gate`.
- Prove a fix / post evidence: the `pr-ab-evidence` skill.
- Forge/harden a skill from session friction: `forge-skill`.
- Re-review a teammate's PR after they reply or push (claimed fix commits on head?): `pr-rereview-after-reply`.
