---
name: relaying-a-go-ahead-to-another-claude-session
description: "Find and message another local Claude Code session: verify its native inbox socket, check whether the requested work is already done, and relay without implying fresh approval. Triggers on: can you speak to this Claude agent, message the peer, cross-session message, .sock, relay my ok, peer-relay, is the other session waiting on me."
---

## More triggers
peer-relay (old name), let the other session know, what is the peer doing, cross-session message, is the other session waiting on me, send the migration note to the peer, tell the other session to go, ask the other agent, the peer asked go on both, file it?, idle notice says, did the peer already do it.

# relaying-a-go-ahead-to-another-claude-session

Checks state before you relay, so the message isn't stale, and words it so the peer can't misread it.

## Find the native session first

For a capability or discovery question, inspect Claude Code's registry before looking for terminal panes or tmux. From any client, this read-only command finds an exact session name:

```bash
jq -s --arg name '<session-name>' '
  .[] | select(.name == $name) |
  {name, pid, procStart, sessionId, cwd, status, peerProtocol, messagingSocketPath}
' ~/.claude/sessions/*.json
```

Verify the returned PID and socket, using the values from that record:

```bash
kill -0 "$pid"
ps -p "$pid" -o pid=,lstart=,comm=
test -S "$socket"
```

Compare the process start time with the registry's `procStart` before relying on a PID (normalize timezone differences first); stale files and recycled PIDs are possible. If several records have the same name, identify the intended process before messaging. Do not dump registry key files or messaging tokens.

Claude Code natively uses `ListAgents` to discover sessions and `SendMessage` to deliver messages. On the same machine, delivery uses the target's Unix inbox socket, commonly `/tmp/cc-socks/<pid>.sock`; read `messagingSocketPath` rather than constructing it. Inside Claude Code, `/status` shows `Peer address` and hooks/Bash receive `CLAUDE_CODE_MESSAGING_SOCKET`.

A different client may lack Claude's native tools. Say so, and distinguish socket discovery from proven delivery. A live PID and socket file establish a candidate endpoint, not a working conversation. Direct socket clients need a verified protocol and must preserve the receiver's inbound controls; do not guess a JSON payload, impersonate another session, or change settings to force acceptance. An acknowledgment alone does not prove Claude read the message. A capability question does not authorize sending a test message.

Use the [official cross-session messaging documentation](https://code.claude.com/docs/en/cross-session-messaging#the-sessions-inbox-socket) for current behavior, especially when asked to check online. Messages may be delivered, held or refused. Do not infer the outcome from socket presence.

## Do this

1. **Check what's already true** (read-only):
   ```bash
   C=${SKILL_DIR:-~/.claude/skills/relaying-a-go-ahead-to-another-claude-session}/check.sh
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

- **Native socket discovery precedes terminal discovery.** A capability check searched tmux and old relay backups before reading the live registry. The user pointed back to `.sock`; the registry immediately supplied the named session's PID and inbox. Check it first and avoid claiming delivery that was never tested.

- **Half the relays over two days were stale.** A "go" on a release candidate that was already cut (its build running), "take the PR out of draft" and "run the deprecation" (both already done, because the user answered the peer directly). Each cost a round trip and a "please don't act on these" correction. Checking first prevents all of them.
- **Harness idle notices are cut off** mid-question: "Go on both?" needed a follow-up message to learn it meant one ticket's PR plus another ticket's deprecation.
- **The peer reads the first line only** in its preview: put the ask there, not a greeting.
- **Peers ask the user in their own session too.** A peer held a ticket until the user answered it directly, which is correct; the relay is a heads-up, and saying "relayed by" keeps that clear.
- Cross-session messages wait in the peer's inbox until its next tool round; don't poll `ListAgents`, use `notify_when_idle`.

## Related

- `watching-another-claude-session-live`: read a peer's transcript when its reply isn't enough.
