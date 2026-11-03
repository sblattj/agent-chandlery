---
name: reading-overflowed-tool-output
description: "Read a tool result or Workflow output that overflowed the context (persisted-output preview, output too large, tasks/<id>.output, tool-results/*.txt): list the newest ones, unwrap the {result} wrapper, show keys and lengths, pull one JSON path, grep, head. Triggers on: tool result too large, the output was truncated, where is the full workflow result, read the persisted output, show me the stats from the swarm run, btr, big tool result, tasks output file, tool-results txt, result exceeded the limit."
---

## More triggers

big-tool-result (old name)

# reading-overflowed-tool-output

`btr.py` finds and slices the files Claude Code writes when a tool result or Workflow return is too big to show inline.

## Do this

```
B=${SKILL_DIR:-~/.claude/skills/reading-overflowed-tool-output}/btr.py
python3 -I $B ls [--sid SESSION] [-n 20]            # newest session: tool-results/*.txt and /tmp/claude-*/.../tasks/*.output, size + kind + first line
python3 -I $B task TASKID --keys                      # a Workflow return: top-level keys with types and lengths
python3 -I $B task TASKID --path stats                # one JSON path (a.b[0] syntax)
python3 -I $B show FILE --grep REGEX --head 20        # any overflow file
python3 -I $B show FILE --len
```

`show` and `task` unwrap the `{"result": ...}` wrapper and the `<persisted-output>` preview automatically. Read-only.

## Why it's built this way (friction mined)

- **Two places.** MCP and Bash overflows land in `~/.claude/projects/<cwd-slug>/<session>/tool-results/*.txt`; Workflow returns land in `/tmp/claude-<uid>/<cwd-slug>/<session>/tasks/<taskId>.output` (on macOS `/tmp` resolves to `/private/tmp`; set `BTR_TMP` if your temp root differs) wrapped in `{summary, logs, result}`. `ls` shows both for the newest session.
- **The inline Workflow result is truncated**, so the stats or the claims list you need are only in the `.output` file. On one swarm run: `--keys` gave `units:list[50], stats:dict(7), claims:list[57]`, `--path stats` gave the agreement numbers.
- **Grep before read.** A 63k-char MCP listing overflow was answerable with `--grep <date> --head 4` instead of loading it.
- Pass `--sid` when the newest session is not the one that produced the file.

## Related

- `fanning-out-a-verified-read-only-swarm` (its `swarm.py save` reads the same `.output`), `fitting-a-50-plus-task-fan-out-under-workflow-limits`.
- `measuring-claude-session-start-tokens`: the other skill that reads session jsonl directly.
