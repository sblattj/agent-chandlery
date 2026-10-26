---
name: kiro-context-probe
description: "Measure what a Kiro CLI agent actually loads into context: global and workspace steering, inclusion modes (always, manual, auto, fileMatch), agent resources, skills, subagents. Runs one headless V3 chat, finds its own session log and lists the loaded docs. Triggers on: what does my kiro agent load, is steering leaking into the lean agent, kiro steering inclusion test, does manual steering stay out, kiro subagent inherits steering, Unresolved steering reference outsideRoot, Agent uses the v3 format."
---

# kiro-context-probe

Answers "which instructions does this Kiro agent start with?" from the session log, not from the docs (they disagreed once). Examples use `lean`, a trimmed custom agent; substitute your own agent names.

## Do this

```bash
P=${SKILL_DIR:-~/.claude/skills/kiro-context-probe}/probe.sh
$P --agent lean --mark "<a heading from your rules>" CANARY_X   # V3: lists steering docs + chars, counts each mark
$P --mark "<a heading from your rules>"                         # the default agent (chat.defaultAgent)
$P --engine v2 --recall                          # V2 logs no steering: ask the model what it was told
```

To test a mode, drop a canary into `~/.kiro/steering/` (`---\ninclusion: manual\n---\nCANARY_MANUAL_1\n`), probe, then **delete it right away**: it is live global steering for every Kiro session on the machine.

## Why it's built this way (friction mined)

- `kiro-cli chat --no-interactive` runs the **V2** engine unless you pass `--agent-engine v3`. V2 writes `~/.kiro/sessions/cli/*.jsonl` with no steering content, so a grep there finds nothing and proves nothing.
- V3 sessions live in `~/.kiro/sessions/<hash>/sess_*/messages.jsonl`. Find yours by `workspacePaths` in `session.json` (the script runs in a fresh `/tmp` dir and matches on its realpath, which on macOS is under `/private`). `ls -t` picked another session's live 700 KB log.
- V3 behavior, measured on kiro-cli 2.32.0: `manual`, `auto` and `fileMatch` files stay out of every agent until triggered. `always` and files with no front matter load into every agent, including files in subfolders of `~/.kiro/steering`.
- A file named `AGENTS.md` in steering ignores inclusion modes. A symlink to your global rules file there loads into every agent, lean included.
- `#[[file:../x.md]]` that points outside `~/.kiro/steering` renders as `[Unresolved steering reference: file:../x.md (outsideRoot)]`. So a wrapper file in steering can't pull in a rules file that lives elsewhere (for example a global `AGENTS.md` in your home dir).
- Agent `resources` (`file://~/rules.md`, `file://~/.kiro/steering/**/*.md`) do load `manual` files, but they don't expand `#[[file:]]` references. That's the per-agent lever: put heavy rules in `resources` of a full agent and keep them out of global steering.
- `includePowers` in an agent makes it V3-only, and `kiro-cli agent set-default` then refuses it ("Agent main uses the v3 format"). Leave the field out of an agent you want as the default on both engines.
- A subagent spawned by delegation (`subAgentName: lean` in the log) still answered from the parent's rules (its records say `agentMode: main`). Trimming steering only helps direct `--agent lean` runs.
- Lean still gets the skills listing. `chat.disableInheritingDefaultResources` turns that off, but it's global and hits every custom agent.
- The recall prompt ("from your loaded instructions only, no tools ... else UNKNOWN") is the fastest cross-engine check. A trimmed agent may cite the home path or a skill description; that's not steering.
- Steering doc ids in the log are `{"id":"file://...","content":...}`. Resource docs aren't in that list, so use `--mark` on a heading you know is in them.

## Related

- `real-start-tokens`: the same question for Claude Code sessions.
