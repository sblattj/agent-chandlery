---
name: skill-hint-hook
description: "Build or tune a UserPromptSubmit hook that ranks skills against the prompt (BM25 over name, description, More triggers) and injects a short hint only on a strong match, so more skills can be name-only. Triggers on: semantic skill hook, skill hint hook, suggest a skill per prompt, skill retriever."
---

# skill-hint-hook

A parked design: build it only when `skill-trigger-ab` shows recall dropping after hiding more skills. The retriever prototype below works today; the hook around it is the remaining work.

In plain words: Claude sees mostly skill names; a tiny script reads each prompt and whispers "try ticket-lookup" only when it's a clear match.

## Do this
```bash
python3 ${SKILL_DIR:-~/.claude/skills/skill-hint-hook}/scripts/retriever.py "pull ticket 1234" 3   # zero deps, ~6ms
# -> [('ticket-lookup', 17.97), ('standup-to-tracker', 6.34), ...]
```
It indexes every `SKILL.md` under `~/.claude/skills` (or `$SKILLS_DIR` if set).

To build the hook:
1. Wrap `rank()` in a script reading the hook JSON on stdin (`prompt` field), print a one-line hint to stdout (UserPromptSubmit stdout is added as context) only if top1 >= ~10 and top1 - top2 is wide.
2. Cache the index; rebuild when any `SKILL.md` mtime changes.
3. For `user-invocable-only` skills the hint can only say "the user can run /name"; Claude can't call them.
4. Register in `~/.claude/settings.json` `hooks.UserPromptSubmit`, then add an arm to `skill-trigger-ab` (hooks run under `claude -p`).

## Why it's built this way (friction mined)
- **Thin margin**: the best off-topic score was 7.1 and the weakest true hit 7.8, so a fixed threshold misfires. Gate on both absolute score and the top1/top2 gap.
- Prototype: top-3 22/22, top-1 19/22 on real prompts.
- **Index the pre-trim description too**: trimmed descriptions keep the old text under `## More triggers` (the convention `skill-diet-audit` uses when it trims) so ranking doesn't lose triggers.
- Expected win: about 1-3k tokens per call. About half a day of work.

## Related
- `skill-trigger-ab`, `skill-diet-audit`.
