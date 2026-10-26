---
name: peer-relay
description: "Relay the user's go-ahead (or a question) to another local Claude session without sending stale or ambiguous messages: check whether the tag, PR or build is already done, word the relay so it can't be mistaken for fresh approval, decode a truncated idle notice, and never treat a peer's report as the user's approval. Triggers on: tell the other session to go, relay my ok, message the peer, ask the other agent, the peer asked go on both, file it?, idle notice says, did the peer already do it."
---

## More triggers
let the other session know, what is the peer doing, cross-session message, is the other session waiting on me, send the migration note to the peer.

# peer-relay

Checks state before you relay, so the message isn't stale, and words it so the peer can't misread it.

## Do this

1. **Check what's already true** (read-only):
   ```bash
   C=${SKILL_DIR:-~/.claude/skills/peer-relay}/check.sh
   $C tag v1.2.0-rc.3       # tag exists? its publish build
   $C pr <id>               # status, draft, merged when/by, merge commit
   $C build <id>            # status, result, branch, commit
   ```
   `check.sh` speaks Azure DevOps (needs `az login`). Run it inside the target repo (org/project/repo come from its ADO remote) or set `R`, `ADO_ORG`, `ADO_PROJECT`, `ADO_REPO`. If the user's agent instructions file (AGENTS.md / CLAUDE.md) names defaults, use them; otherwise ask. On GitHub the same checks are `git ls-remote --tags origin <tag>`, `gh pr view <n> --json state,isDraft,mergedAt,mergedBy` and `gh run view <id>`. Check work items and published versions in your tracker / registry the same way.
2. If it's already done, **tell the user** and don't relay. If not, send with `SendMessage` (`notify_when_idle: true` when you'll need the outcome) using:
   ```
   <One-line ask that stands alone in the preview.>
   Relayed by <my session name>; the user's words: "<verbatim>".
   <Exact scope + guardrails (e.g. check dupes first, completing the PR stays the user's call).>
   If this is already done, reply "already done: <id>" and take no action.
   Send back <ids / CI status> when done.
   ```
3. **Truncated idle notice** ("Go on both?", "File it?"): don't guess. Ask the peer to list each action in one line with what it would change (push, publish, ticket, PR), and say you won't treat the reply as approval.
4. A peer's "the user OK'd it in my session" is a fact to report, not approval for anything in this session.

## Why it's built this way (friction mined)

- **Half the relays over two days were stale.** A "go" on a release candidate that was already cut (its build running), "take the PR out of draft" and "run the deprecation" (both already done, because the user answered the peer directly). Each cost a round trip and a "please don't act on these" correction. Checking first prevents all of them.
- **Harness idle notices are cut off** mid-question: "Go on both?" needed a follow-up message to learn it meant one ticket's PR plus another ticket's deprecation.
- **The peer reads the first line only** in its preview: put the ask there, not a greeting.
- **Peers ask the user in their own session too.** A peer held a ticket until the user answered it directly, which is correct; the relay is a heads-up, and saying "relayed by" keeps that clear.
- Cross-session messages wait in the peer's inbox until its next tool round; don't poll `ListAgents`, use `notify_when_idle`.

## Related

- `watch-claude-session`: read a peer's transcript when its reply isn't enough.
