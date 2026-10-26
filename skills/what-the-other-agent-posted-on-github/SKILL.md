---
name: what-the-other-agent-posted-on-github
description: "What did another agent do on a GitHub repo since a time: new releases with notes plus new issue/PR comments, read as the owner. Triggers on: they replied, check their comment, the agent posted a followup, what new release did they put out."
---

## More triggers
is another release out, did the agent address my comment, what changed on #<n>.

# What the other agent posted on GitHub

## Do this

```zsh
${SKILL_DIR:-~/.claude/skills/what-the-other-agent-posted-on-github}/check.sh <owner>/<repo> 3h <n>   # repo, since (Nh or ISO), optional issue
```
Read-only. The repo defaults to the current checkout's GitHub repo. `AS=<login>` overrides the gh account (default: the repo owner, so private repos of a personal account read fine while another account is active). `Nh` uses BSD `date -v` (macOS); elsewhere pass an ISO timestamp.

## Why it's built this way (friction mined)

- The agent's answer often lands **as a release note first** ("Part of #<n>") and the comment
  minutes later, or the other way round. Check both; if the user says "they replied" and
  nothing shows, re-run in a minute rather than concluding nothing happened.
- Use `issues/comments?since=` repo-wide: replies can land on a linked PR or a sibling issue.
- Long bot review summaries (comments carrying a `<!-- prxref-summary -->` marker) are collapsed to their heading; add your own bot's marker to the jq filter the same way.
- A new release usually means: gate it (install, run your smoke checks) before building on it.

## Related

- `scrub-and-open-issue` (replying as the repo owner), `pr-activity-since-push`, `watch-claude-session`.
