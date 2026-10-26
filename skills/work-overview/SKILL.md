---
name: work-overview
description: "Produce a high-level narrative overview of what ONE person shipped across specific LOCAL repos over a date range, straight from git log: terminal prose, no HTML, no org discovery. Repos, since-date, author and ticket pattern are optional arguments (else cwd repo, 14 days, git user.name). Triggers on: high level overview of my work, what did I work on, what have I done since <date>, summarize my commits, recap my work in <repo>, what did I ship this month in these repos."
---

# Work Overview (single person, local repos, terminal)

Answers "high-level overview of <person>'s work from <date> til now" for a given set of local repos. Reads git history and writes a per-repo thematic narrative plus an overall arc.

## Do this

```bash
O=${SKILL_DIR:-~/.claude/skills/work-overview}/overview.sh
bash $O --since 2026-09-01 ~/dev/acme-api ~/dev/acme-web
SINCE=2026-08-01 AUTHOR='Doe' REPOS="$HOME/dev/acme-api" bash $O
bash $O --ticket-re 'PROJ-[0-9]+' ~/dev/acme-api      # tracker ids in your own format
bash $O                                               # cwd repo, last 14 days, git user.name
```

Resolving inputs (nothing is baked in):
- **Repos:** what the user named; else `REPOS`; else the cwd git repo; else the repos the user's agent instructions file (AGENTS.md / CLAUDE.md) names as defaults, if any; else ask.
- **Since:** what the user said; else that same defaults section; else 14 days ago (the script says so).
- **Author:** `--author` / `AUTHOR`; else `git config user.name`. Prefer a distinctive NAME substring (a last name) over an email.
- **Tickets:** `--ticket-re` / `TICKET_RE` (extended regex); default matches `#1234`, `XY#<id>` and `PROJ-123` shapes.

Then synthesize (don't dump the raw log): per repo give branch + scale (commits, files, +/-), then 3-5 thematic threads grouped from the subjects/tickets, then one "overall arc" line tying the repos together. Ask at the end whether to go deeper on a thread, pull merged PRs vs local commits, or check uncommitted work.

The script prints, per repo: identities matched, commits/day, no-merge churn totals, top referenced tickets, and every commit subject grouped by day. That is the raw material for the narrative.

## Why it's built this way (friction mined)

- **Author match is a NAME substring (`--author='Doe'`), not an email.** People commit under a work email, a personal email, and name variants (e.g. `jane-doe-<org>`). Filtering by one email silently drops commits. The script prints the matched identities so you can confirm coverage.
- **Churn totals must exclude merges.** `--no-merges --shortstat --format=''` piped to an awk summer: merge commits double-count diffs and blow up the numbers.
- **Just read the current branch, never switch it.** Main worktrees may sit on a long-lived integration branch that must stay checked out. The script only reads `git rev-parse --abbrev-ref HEAD`.
- **Tickets are the theme signal.** Ticket-id counts cluster the work fast (e.g. #1234 + #1235 = a coverage/test blitz) without reading all 300 subjects.
- **Run it as a `bash` script file.** zsh won't word-split unquoted vars; the script uses arrays and is invoked with `bash`.
- **Scale sanity:** a busy monorepo can hit ~320 commits / ~2.3k files over ~2 weeks next to a side repo at ~84 / ~730. Expect the big number to be dominated by a couple of high-volume days (test/CI sweeps), so cadence-per-day matters in the narrative.

## Related

- `evidence-dump`: the same commits plus GitHub / Azure DevOps PRs, frozen into files for reconciling commitments.
- `pr-activity-since-push`: what happened on your open PRs since you last pushed.
