---
name: skill-diet-audit
description: "Read-only audit of Claude Code skill context cost: per-skill usage from session logs vs current skillOverrides, suggested on/name-only/hidden changes, descriptions over the 600-char cap. Triggers on: skill diet, which skills are unused, audit my skills, skills list too big, trim skill descriptions, built-in skills in the listing, apply skillOverrides, did my overrides stick."
---

# skill-diet-audit

Monthly check that keeps the skills listing small as skills pile up.

In plain words: every listed skill's description rides along in every session. This finds the ones nobody uses (hide them) and the ones that talk too much (trim them).

## Do this
```bash
P=${SKILL_DIR:-~/.claude/skills/skill-diet-audit}/scripts
C=/tmp/skill-diet/skills-usage.csv; mkdir -p "$(dirname "$C")"
python3 $P/skill-usage.py --all-projects -o $C   # scans every project (default is only the cwd project), interactive sessions only (--include-headless for -p), about 1 min
python3 $P/audit.py $C            # table: Now vs Suggest per skill, over-cap descriptions, listed descriptions naming a hidden skill; --cap 600 --rare 3 --new-days 30 [--hide]
python3 $P/skill-lint.py ~/.claude/skills --settings ~/.claude/settings.json   # fully listed skills over the 600-char cap
```
All scripts are standard-library Python, read-only, and honor `$CLAUDE_CONFIG_DIR` (default `~/.claude`).

Then:
1. Find the live settings file first: `readlink ~/.claude/settings.json`. If it is a symlink into a dotfiles repo, edit that repo path, never through the symlink with `sed -i`. Back it up (`cp` with a date suffix) before changing `skillOverrides`.
2. Apply suggestions you agree with. States: `on`, `name-only` (name listed, description not), `user-invocable-only` (hidden from Claude, `/name` still works), `off`.
3. Trim over-cap descriptions: keep the distinctive triggers, move the rest to a `## More triggers` line after the frontmatter. `keep-original.py --backup <pre-trim copy of the skills dir> <names...>` appends the pre-trim description there so a hint retriever still sees it.
4. Before adopting more than a couple of `name-only` moves, run `skill-trigger-ab`.
5. Verify the live file holds every intended value (one PASS/FAIL line per skill, read through `~/.claude/settings.json`), then commit and push the settings repo if there is one.
6. Re-measure a real interactive start with `real-start-tokens`. Headless (`-p`) measurements read low.

## Why it's built this way (friction mined)
- **Typed-only skills** (ones the user only ever runs as `/name`) never need the listing: suggest hidden.
- **New skills get probation**: undecided skills under 30 days old are suggested `name-only`, never hidden; promoted to `on` after more than 3 uses (`--new-days`, `--rare`). Explicit hide decisions are kept. 5 skills arrived mid-diet (62 -> 67) and pushed the baseline back up.
- **Don't count your own test runs as usage.** A/B and ablation runs are `claude -p` sessions that write real logs; they inflated one skill from 4 to 59 uses. `skill-usage.py` skips every record whose `entrypoint` isn't `cli` (all A/B, ablation and eval runs are `-p`/SDK).
- **Skip skills with `disable-model-invocation: true`.** They are already out of the listing, so a `name-only` suggestion for them saves nothing. In one pass 13 of 20 suggested trims were these (`grep -l '^disable-model-invocation: true' ~/.claude/skills/*/SKILL.md`); the real saving was the other 7.
- **The usage CSV mixes in built-in commands** (`compact`, `exit`, `model`, `effort`, `copy`) and suggests them `user-invocable-only`. Ignore those rows.
- **Overrides live in whichever repo owns the settings symlink.** When the symlink moved from one repo to another, 6 of 8 changes made the day before silently stopped applying (95 entries became 47). Re-check the `readlink` before trusting an earlier diet.
- **Name-only skills don't count toward the cap**: their description isn't loaded.
- **Built-in and plugin skills are in the listing too** (dataviz 1,447 chars, claude-api 1,082, update-config 707, plus /loop, /schedule, /init...). They aren't under `~/.claude/skills`, so the usage and audit scripts never see them, yet `skillOverrides` works on them. Moving 11 rarely used built-ins to `name-only` took the real listing 17.4k to 12.3k chars and the start 34.7k to 32.9k tokens. Spot-check: claude-api 2/2, update-config 2/2, dataviz 4/6 vs 4/4 fully listed. Get the full list from the `skill_listing` attachment in a fresh session JSONL; count usage with `rg -c '"skill":"<name>"'`.
- **Report real session starts, not `-p`.** A headless baseline ran about 21k tokens under a real interactive start.
- **Pointer targets stay listed.** If CLAUDE.md says "load the X skill", X must be at least `name-only`; `audit.py` keeps an explicit state for typed-only skills instead of suggesting hidden.
- **Hiding a skill: grep other descriptions for its name first.** A listed skill that says "use X instead" makes Claude try the hidden X and hit `disabled for model invocation`. Reword to "the user command /X".
- **Skills that must not be named in a shared or public settings file** (private skills): no user-wide private settings layer exists (`settings.local.json` in `~` only applies when the project is `~`). Instead shorten the description in the skill's own SKILL.md to one line, keeping the old text under `## More triggers` (that's what `keep-original.py` does). Run `skill-trigger-ab` first; keep the full description for any skill that regresses (one pass: 26 trimmed, 4 kept, start tokens -21%).
- **Skills owned by another session or person**: edit only the scope sentence, and say so.
- One measured result: main session 35.9k -> 32.0k start tokens with 30+ skills moved off `on` and 14 descriptions trimmed.

## Related
- `skill-trigger-ab`, `real-start-tokens`, `forge-skill` (600-char cap rule), `skill-hint-hook`.
