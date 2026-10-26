---
name: swarm-unit-pack
description: "Pack a big /swarm or Workflow fan-out (50+ units) into one small args file: per-unit JSON files plus a shared _RULES.md, one-line prompts that point at them, and a size check. Avoids the Workflow args cap (97KB of inline prompts failed, 11KB of file pointers ran). Triggers on: workflow args too large, swarm has too many units, fan out over 50 files, pack units for swarm, one file per unit, swarm unit pack, Workflow failed with big args, check the args size, split the prompt into unit files."
---

# swarm-unit-pack

Turns `items.json` (a JSON array, each item with an `id`) into `BASE/<id>.json`, `BASE/_RULES.md`, `BASE/_units.json` and `BASE/_args.json` ready for `swarm.workflow.js` (from the `swarm` skill).

## Do this

```
P=${SKILL_DIR:-~/.claude/skills/swarm-unit-pack}
python3 -I $P/pack.py items.json --base /tmp/<job> --rules RULES.md [--tier sonnet] [--goal TEXT] [--compare] [--mcp] [--prefix r]
python3 -I $P/pack.py check /tmp/<job>/_args.json
```

Then `Workflow({scriptPath: "<home>/.claude/skills/swarm/swarm.workflow.js", args: <contents of _args.json>})` (the Workflow tool wants an absolute path). `check` prints bytes per unit and warns above 30,000 bytes total.

- `RULES.md` is the shared instruction sheet every unit follows; it is copied to `_RULES.md` and referenced in each one-line prompt.
- `--goal` is prefixed to an auto-generated line listing the rules path, the unit-file pattern and "All paths absolute" so verifiers can find the inputs.
- The default tier is `sonnet`; pass `--tier haiku` when each unit is a small lookup.
- Read-only: it only writes under `--base`.

## Why it's built this way (friction mined)

- **Inline prompts do not scale.** 60 per-document units with full instructions inlined were 97KB and the Workflow call failed. The same 60 as one-line pointers were 11KB and ran. Checked: 5 units = 1.3KB, the real 60-unit file = 11.3KB.
- **Verifiers only see goal + claim + evidence.** Put the absolute base path in the goal, or skeptics return "unclear" for relative paths.
- **Shared rules in one file, not in every prompt.** Changing the rules then means one edit and a cheap rerun.
- **Stable ids become unit ids and claim keys**, so `swarm.py drift` can match reruns.

## Related

- `swarm`, `xx`: the engines this packs for.
- `big-tool-result`: reading the run's output after it finishes.
