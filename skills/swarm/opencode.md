# Swarm without a Workflow tool (OpenCode and similar clients)

Used instead of SKILL.md when the client has no Workflow tool, only a subagent/`task` call. If you wire `/swarm` up as a command in such a client (for OpenCode, a file under `~/.config/opencode/command/`), this is the design reference behind it.

Dispatches up to 100 (default cap) subagents from the main session in
staggered waves, with file-backed run state that survives compaction and a
verifier wave that re-checks load-bearing results. `/swarm` is the command
entry point; this skill is the design reference and the auto-trigger path
when the user describes swarming without typing the command.

Sizing: 1-3 seats is a plain parallel fan-out, not a swarm. The cap is a ceiling,
not a quota: merge trivial tasks, dispatch only as many seats as the work
actually needs.

## Architecture

- Orchestrator: the main session. Flat fan-out, ONE level of delegation.
  Workers never spawn workers; briefs never mention subagents at all.
- Waves: at most 8 seats in flight at once, launched as parallel `task` calls
  in a single block. Next wave starts when the current one returns.
- Tiers, rated per seat on a 1-100 scale: read-only research runs on a
  read-only explore agent; rated 50 or below runs on a light (cheap model)
  agent; above 50 runs on a standard agent. Map these to the agent types your
  client defines (OpenCode ships `explore`; define `light` and `standard`).
- Modes: research (read-only, no isolation needed), impl (each writing seat
  owns a disjoint set of files named in its brief; un-partitionable writes are
  sequenced across waves), mixed (both).

## Safe task-call recipe (every dispatch)

Exactly three fields: `description` (3-5 word label), `subagent_type`,
`prompt`. Never `task_id`, `command`, `model`, or anything else. On error:
read it, fix the named field, retry ONCE. Three identical consecutive
failing calls is a doom loop: abort the run and report.

## Run state (ground truth on disk)

- Run dir: `${SWARM_STATE:-~/.local/state/swarm}/<run-id>/`.
- `manifest.md`: `| seat | wave | type | brief | status | out | verdict |`.
  Status: pending, dispatched, returned, failed, verified, redo. Rewrite the
  whole file after every wave. After any compaction, re-read the manifest
  before continuing; the disk file outranks memory.
- `seat-NN.md` per seat: sections RESULT, EVIDENCE (commands run plus real
  output), FILES TOUCHED, FRICTION. Verifiers write `seat-NN-verify.md`.

## Seat brief template

Every brief is self-contained and carries: the goal; exact scope and owned
files; concrete steps; the output contract above; honesty rules (report
failure as failure, no padding, verify your own work before returning); and
a FRICTION section in the report.

## Verifier wave

After doer seats return, pick load-bearing results (files on disk, claims
other seats depend on) and dispatch one verifier per roughly 5 doers, within
the cap. The verifier reads the seat file AND the artifact itself, applies
Claim -> Evidence -> Verdict, and writes a pass or fail with evidence. Fail
dispatches exactly ONE redo seat whose brief quotes the failure note; the
redo overwrites the same seat file.

## Failure handling

- Seat returns nothing or writes no file: ONE retry with a note of what went
  wrong.
- Two consecutive waves fail more than 30% of their seats: stop early, record
  why in the manifest, report state.
- Doom loop (3+ identical consecutive failing calls): abort, report.

## Finish

The orchestrator integrates results into the final artifact itself, writes it
to disk, verifies it exists and is complete, updates the manifest, and
reports: seats dispatched and verified, failures, artifact path, friction.
Done means observed on disk, never inferred from a worker's self-report.
