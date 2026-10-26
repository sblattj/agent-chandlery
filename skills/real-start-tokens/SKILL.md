---
name: real-start-tokens
description: "Read the real starting context (tokens before the first reply) of recent Claude Code sessions straight from the session jsonl, with a per-block split (skills listing, CLAUDE.md, MCP, deferred tools, agents). Works without /context, including in agent view. Triggers on: what does a fresh session start at, real start tokens, how big is my starting context, did the context diet stick, compare start tokens before and after."
---

# real-start-tokens

```bash
S=${SKILL_DIR:-~/.claude/skills/real-start-tokens}/scripts/start_tokens.py
python3 $S                 # newest 5 fresh interactive sessions of THIS project (cwd)
python3 $S --all-projects  # across every project
python3 $S --last 20       # more history
python3 $S X.jsonl         # specific sessions
#   --dir ~/.claude/projects/<proj>   one project   --project PATH   --all-entrypoints   include -p/sdk   --json
# honors CLAUDE_CONFIG_DIR; helper lib/ccpaths.py ships beside scripts/
```

**Start** is exact: the first assistant `usage` (input + cache_creation + cache_read). Block columns are attachment chars / 4, so estimates. The system prompt and tool schemas aren't logged; they are the rest.

## Gotchas (all hit in real measuring)
- **Only `entrypoint: cli` is a real start.** A `claude -p` run reads ~21k low (no Artifact tool, a smaller system prompt), so the default filter drops it.
- **Rows are keyed by session start time.** File mtime moves whenever a session is resumed, so a morning session looked like it ran after the diet.
- **Compare like with like.** A resumed or compacted session starts with its summary, and a pasted image or long prompt adds to it. For a clean number, open a fresh session with a one-line prompt.
- **Agent view pre-warms sessions,** so the first session after a settings change can still carry the old settings. Measure twice.
- `/context` isn't available in agent view; this script is how you get the number there.

## Related
- `skill-diet-audit`: shrinking the skills listing.
- Turning off big built-in tools you don't use (one tool's schema and prompt were the biggest single lever, ~16.5k).
- `kiro-context-probe`: the same question for Kiro CLI agents (steering, resources, subagents).
