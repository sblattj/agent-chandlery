---
name: skill-trigger-ab
description: "A/B whether skills still fire after changing skillOverrides or descriptions, using real prompts mined from session logs: recall, wrong skill, false fires, start tokens, Wilson CI + McNemar. Triggers on: do my skills still trigger, A/B skill overrides, test name-only skills, skill fires on the wrong prompt, hidden skill makes prompts fire nothing, rep-level paired bound."
---

# skill-trigger-ab

Proves a skill-visibility change (name-only, hidden, a reworded description) didn't break which skill Claude picks.

## Do this
Scripts live in `scripts/` (shared helper `lib/ccpaths.py`). Full flag docs: `scripts/README.md`, or `-h` on any script. Self-tests (no network): `cd scripts && python3 -m unittest discover -s tests`.
```bash
P=${SKILL_DIR:-~/.claude/skills/skill-trigger-ab}/scripts; W=${AB_WORK:-~/skill-ab}/ab-$(date +%m%d); mkdir -p $W
python3 $P/mine.py ~/.claude/projects --all-projects --out $W/candidates.jsonl --days 30 --max-negatives 150   # interactive sessions only
python3 $P/filter.py $W/candidates.jsonl --out $W/cases.jsonl --model claude-haiku-5-5   # Haiku 5.5 judge (--model required, bare haiku rejected) keeps standalone prompts
python3 $P/make_arms.py --skills-dir ~/.claude/skills --out $W/arms --base-settings ~/.claude/settings.json \
    --arm current --arm after --set 'after:some-skill=name-only'      # first --arm = baseline; ARM:GLOB=STATE, in order
python3 $P/run.py --cases $W/cases.jsonl --arms $W/arms --out $W/results.jsonl --reps 2 --workers 6 --model sonnet   # resumable; tail -f $W/results.jsonl.progress
python3 $P/report.py $W/results.jsonl                                 # Wilson 95% CI + paired McNemar vs the first arm
```
Optional: `synth.py` adds synthetic positives for skills with few real ones (excluded from recall by default); `quick_ab.py --prompts F --a A.json --b B.json` for a small hand-written check; `make_rename_arms.py` for name tests.
For a narrow fix (one description), make a small cases file and point `--cases`/`--out` at it. Use `--reps 3`.
Keep each round's work dir (`$W`); later rounds compare against it.

Reference numbers from one real run (448 runs/round, Sonnet): before vs adopted recall 78% vs 78%, McNemar p = 1.0,
start tokens 18.8k vs 16.9k. About 20 minutes per round at 8 jobs.

## Why it's built this way (friction mined)
- **Label noise is the main risk.** A turn that called 2 skills scored one as a miss until cases got an `accept` list.
  Mined "negatives" (no Skill called) are sometimes real positives: 2 of 4 negatives for a ticket-tracker skill were relabeled. Read negatives that fire before trusting the false-fire rate.
- **Hidden skills can't fire.** `user-invocable-only` skills are excluded from recall in report.py, or the arm looks broken.
- **Context-dependent prompts** ("yes", "do 2 and 3", "read the prompt here <path>") are noise; filter.py drops most, a few slip through.
- **Read-only runs**: `--tools Skill Read Grep Glob`, empty MCP, `--max-turns 2`. Detect fires via `Skill` tool_use in stream-json.
- **Verify the edit landed before the "before" run.** A Python replace hit an AssertionError (anchor mismatch) once, so the "after" run was really baseline. Check the file, then run.
- **Name-only too aggressive raises wrong picks** (top-15 arm: 2% -> 7%): the model guesses a similarly named skill. Keep look-alike skills fully listed.
- **Runs read the live SKILL.md files.** Don't edit any skill while `run.py` is going, or later reps test a different arm. Apply description trims only after the report.
- **A name-only arm is a stricter stand-in for "short description"**: if the name-only arm holds recall, a one-line description will too. Look at per-skill regressions, not just the totals: in one round real-case recall rose 54% to 61% while 3 skills dropped 2/2 to 0/2 on synthetic prompts, so those kept their full descriptions.
- **Most wrong picks come from one broad description**, not from name-only. A scope sentence ("status only: to cut a release use X"; "read-only, one item: not for creating or listing many") fixes it: one tracker skill's false fires went 5/6 -> 2/6.

- **Never name a hidden skill as the alternative in a description.** "use standup-to-tracker instead" made Claude call the hidden skill, which fails with `Skill standup-to-tracker is disabled for model invocation in skillOverrides settings` (a wasted turn). Point at the user command instead: "is the user command /standup-to-tracker (suggest it, do not call it)". `invoked` in results counts these failed attempts too.
- **Check a "wrong pick" against the arm before fixing a description**: if the expected skill is hidden in that arm, report.py already excluded it; an ad-hoc breakdown won't.

- **Names are the whole signal for name-only skills.** Test renames with `make_rename_arms.py --skills-dir D --base ARM.json --rename RENAME.json --name NAME --out ARMS [--prefix X]`: renamed copies go in a per-arm cwd as project skills, the originals are set to `off`, and run.py maps invoked names back (`arms/ARM.meta.json`). In one round, trigger-shaped names took 7 opaque name-only skills from 49% to 90% recall on fresh prompts (McNemar p<0.0001) with other skills flat. A `use-this-skill-when-` prefix gained nothing over the same names without it and cost ~300 start tokens. Rename only opaque names (`boil-the-ocean` 0/15 -> 10/15). Clear ones lost ground when renamed (`pr-preflight-review` 6 -> 3).
- **Prompts must not come from the names.** Have a writer that never sees the new names write prompts from the SKILL.md. Prompts that name a skill outright ("update the release-notes skill") miss after a rename; that's a real cost, because typed old names stop working.

- **Hiding a skill doesn't send Claude to the next-best visible one.** When a prompt's `accept` list mixes hidden and
  visible skills, the hidden arm often fires nothing at all. Score the split separately: in one round a 27-item hide list
  was -4.5 pp [-7.1, -1.9] on prompts with a visible target. The prompts with no hidden alternative alone were
  -2.2 pp [-4.6, +0.1], and 4 mixed prompts carried the loss. Un-hide what those prompts fired instead of dropping the cut.
- **Pair at the rep level.** A per-case majority McNemar (p ~0.15) called the same data "no difference" that the
  rep-level paired bound showed was outside a 5 pp margin. Report the paired difference and its bound per rep.
- **A run cut short by a usage limit is not a result.** Once more than ~20% of calls error (29/60 after a limit hit),
  stop and rerun after the reset. Don't score the survivors as a verification.

## Related
- `skill-diet-audit`: finds what to hide or trim; this skill checks it was safe.
- `real-start-tokens`: measures the start-token side of a change from real sessions.
- `skill-hint-hook`: next step if hiding more skills drops recall.
