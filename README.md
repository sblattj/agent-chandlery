# agent-chandlery

**Agent skills and goal-state loops for Claude Code, Kiro and Codex.** Fan-out with verification, evidence-first PRs, stacked PRs, skill hygiene, and a goal file that keeps an agent working until the job is done with proof.

A chandlery is the shop that outfits a ship before it sails. This one outfits coding agents: plain `SKILL.md` folders any skills-aware client can load, plus a zero-dependency CLI to install them and run a goal loop.

```bash
npx github:sblattj/agent-chandlery list
npx github:sblattj/agent-chandlery install --client claude --client kiro      # into ./.claude/skills and ./.kiro/skills
npx github:sblattj/agent-chandlery goal set "make the test suite pass" --success "npm test exits 0"
```

## What's inside

| Skill | What it does |
|---|---|
| `goal-state` | One goal file per project: objective, success criteria, a plan whose actions close only with Claim / Evidence / Verdict, a clock and turn budget, and a stop hook that keeps the agent going. |

More skills are being ported in; `chandlery list` shows what this version ships.

## Install

Not on the npm registry yet: run it straight from GitHub with `npx github:sblattj/agent-chandlery`, or clone and `npm link` to get `chandlery` on your PATH.

**Per project** (copies, so the repo carries them):

```bash
npx github:sblattj/agent-chandlery install --client claude              # .claude/skills/
npx github:sblattj/agent-chandlery install --client kiro                # .kiro/skills/
npx github:sblattj/agent-chandlery install --client codex               # .agents/skills/
npx github:sblattj/agent-chandlery install --only goal-state --dry-run
```

**For your user** (all projects): add `--scope user` (`~/.claude/skills`, `~/.kiro/skills`, `~/.codex/skills`). Add `--link` to symlink a clone instead of copying, so `git pull` updates them.

Install never overwrites a skill folder it didn't create (it marks its own with `.chandlery.json`) unless you pass `--force`.

**Dotfiles-style linkers:** `manifest.json` lists `skills/* -> ~/.claude/skills/` with paths relative to the manifest, for linkers that accept extra manifests.

## Goal state

```bash
chandlery goal set "Ship the parser fix" --success "npm test passes" --max-minutes 240
chandlery goal plan add a1 "failing test first"
chandlery goal act a1 done --claim "test fails before the fix" --evidence "node --test: 1 fail" --verdict pass
chandlery goal complete --summary "fixed" --evidence "npm test: 48 pass"
chandlery goal hook install          # Claude Code Stop hook: keep going while the goal is active
```

The CLI is the only writer, so the rules hold:

- an action is `done` only with a claim, evidence and a passing verdict;
- the goal completes only with evidence and no open actions;
- `block` needs a concrete blocker only a human can clear;
- the budget (8 hours per window by default, optional turn and token caps) wraps up at 80% with one handoff turn, then pauses;
- ten turns with no plan change pauses a stalled run.

State lives in `.chandlery/goal.json` (atomic writes, mode 0600) with an append-only ledger beside it. Full reference: [skills/goal-state/SKILL.md](skills/goal-state/SKILL.md).

The design comes from [opencode-goal-pro-max-complete-plugin](https://github.com/sblattj/opencode-goal-pro-max-complete-plugin), a session-scoped `/goal` plugin for OpenCode by the same author, rebuilt here to be client-neutral: a file, a CLI and a stop hook instead of a host plugin API.

## Clients

| Client | Project dir | User dir | Keep-going hook |
|---|---|---|---|
| Claude Code | `.claude/skills` | `~/.claude/skills` | `chandlery goal hook install` (Stop hook) |
| Kiro | `.kiro/skills` | `~/.kiro/skills` | run `chandlery goal turn` at the end of a turn |
| Codex | `.agents/skills` | `~/.codex/skills` | run `chandlery goal turn` at the end of a turn |

## Development

```bash
node --test test/*.test.mjs
node scripts/scrub-check.mjs        # public-repo leak gate: home paths, tracker ids, emails, tokens
```

Node 18 or newer, no dependencies. Each skill is a folder with a `SKILL.md` whose frontmatter `name` matches the folder and whose `description` stays under 600 characters, because every description sits in every session's context.

## License

MIT
