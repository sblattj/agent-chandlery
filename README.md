# agent-chandlery

**36 agent skills and a goal-state loop for Claude Code, Kiro and Codex.** Fan-out with verification, evidence-first PRs, stacked PRs, skill hygiene, and a goal file that keeps an agent working until the job is done with proof.

A chandlery is the shop that outfits a ship before it sails. This one outfits coding agents: plain `SKILL.md` folders any skills-aware client can load, plus a zero-dependency CLI to install them and run a goal loop.

```bash
npx github:sblattj/agent-chandlery list
npx github:sblattj/agent-chandlery install --client claude --client kiro      # into ./.claude/skills and ./.kiro/skills
npx github:sblattj/agent-chandlery goal set "make the test suite pass" --success "npm test exits 0"
```

## What's inside

**Goal loops and verification**

| Skill | What it does |
|---|---|
| [`goal-state`](skills/goal-state/SKILL.md) | One goal file per project: objective, success criteria, a plan whose actions close only with Claim / Evidence / Verdict, a clock and turn budget, and a stop hook that keeps the agent going. |
| [`going-all-in-or-about-to-claim-done`](skills/going-all-in-or-about-to-claim-done/SKILL.md) | Maximal-ambition delivery gated by an evidence ladder before anything is called done. |
| [`swarm`](skills/swarm/SKILL.md) | Read-only fan-out: split a question into small units, run them on cheap agents, verify every claim. |
| [`xx`](skills/xx/SKILL.md) | The write-capable swarm: fan out implementation units, verify, integrate. |
| [`swarm-prompt`](skills/swarm-prompt/SKILL.md) | Write a ready-to-hand-off fan-out prompt for an orchestrator agent. |
| [`swarm-unit-pack`](skills/swarm-unit-pack/SKILL.md) | Pack a 50+ unit fan-out into per-unit files so the workflow args stay small. |
| [`big-tool-result`](skills/big-tool-result/SKILL.md) | Read a tool result or workflow output that overflowed the context. |

**Pull requests**

| Skill | What it does |
|---|---|
| [`pr-ab-evidence`](skills/pr-ab-evidence/SKILL.md) | Red-to-green A/B proof that a bug-fix PR fixes the bug: same test, base vs fix. |
| [`pr-logic-trail`](skills/pr-logic-trail/SKILL.md) | A logic-only HTML walkthrough of a PR, ordered by the path a request travels. |
| [`pr-activity-since-push`](skills/pr-activity-since-push/SKILL.md) | What happened on your open PRs since your last push, and who owns the next move. |
| [`pr-approval-gate`](skills/pr-approval-gate/SKILL.md) | What still blocks each open PR: approvals, CODEOWNERS rules, draft, behind, conflicts. |
| [`pr-rereview-after-reply`](skills/pr-rereview-after-reply/SKILL.md) | Re-review after the author replies: check every claimed fix is really on the head. |
| [`resolve-pr-threads-and-conflicts-and-merge`](skills/resolve-pr-threads-and-conflicts-and-merge/SKILL.md) | Land an approved PR: answer and resolve threads, fix conflicts, wait for CI, merge. |
| [`opening-a-stacked-pr-sequence`](skills/opening-a-stacked-pr-sequence/SKILL.md) | Open dependent PRs in the right order with the right bases. |
| [`landing-stacked-prs`](skills/landing-stacked-prs/SKILL.md) | Land a stack of PRs one layer at a time. |
| [`what-the-other-agent-posted-on-github`](skills/what-the-other-agent-posted-on-github/SKILL.md) | What another agent released or commented on a repo since a time. |
| [`scrub-and-open-issue`](skills/scrub-and-open-issue/SKILL.md) | Scrub internal identifiers from an issue, then file it as the repo owner, never a work account. |

**Skills and context**

| Skill | What it does |
|---|---|
| [`forge-skill`](skills/forge-skill/SKILL.md) | Turn what just happened in a session into a reusable skill by mining the friction. |
| [`skill-diet-audit`](skills/skill-diet-audit/SKILL.md) | Per-skill usage vs context cost from session logs, with trim suggestions. |
| [`skill-trigger-ab`](skills/skill-trigger-ab/SKILL.md) | A/B whether skills still fire after changing their descriptions or overrides. |
| [`skill-hint-hook`](skills/skill-hint-hook/SKILL.md) | A prompt hook that ranks skills against the prompt and hints the best match. |
| [`real-start-tokens`](skills/real-start-tokens/SKILL.md) | The real starting context of recent sessions, split by block. |
| [`kiro-context-probe`](skills/kiro-context-probe/SKILL.md) | What a Kiro CLI agent actually loads into context. |
| [`finding-claude-session-gating-logic`](skills/finding-claude-session-gating-logic/SKILL.md) | Why a Claude Code feature is refused: find the gate in the installed bundle. |
| [`watch-claude-session`](skills/watch-claude-session/SKILL.md) | Find and follow another session's transcript. |
| [`peer-relay`](skills/peer-relay/SKILL.md) | Relay a go-ahead to another agent session without sending a stale one. |

**Code understanding and visuals**

| Skill | What it does |
|---|---|
| [`codebase-memory`](skills/codebase-memory/SKILL.md) | Structural code questions over a code knowledge graph: callers, call chains, architecture. |
| [`cbm-index`](skills/cbm-index/SKILL.md) | Index a repo into that graph the right way: survey, fitted ignore file, full mode. |
| [`explain-concept`](skills/explain-concept/SKILL.md) | Explain a code concept grounded in real snippets, with a diagram when it helps. |
| [`sketch`](skills/sketch/SKILL.md) | A styled local HTML explainer with hand-drawn SVG diagrams, linted in light and dark. |
| [`narrated-screenshot`](skills/narrated-screenshot/SKILL.md) | A self-explaining A/B screenshot with captions and a verdict. |
| [`narrated-ab-video`](skills/narrated-ab-video/SKILL.md) | A narrated A/B proof video from recorded browser runs. |
| [`cdp-route-snapshots`](skills/cdp-route-snapshots/SKILL.md) | ARIA snapshots of a list of routes through a CDP browser. |

**Reporting and environments**

| Skill | What it does |
|---|---|
| [`work-overview`](skills/work-overview/SKILL.md) | A narrative overview of what one person shipped across local repos. |
| [`evidence-dump`](skills/evidence-dump/SKILL.md) | Dump shipped-work evidence (PRs, commits) into one folder for reconciling. |
| [`windows-vm-repro`](skills/windows-vm-repro/SKILL.md) | Reproduce Windows-only bugs from a Mac through a Parallels VM. |

`chandlery list` shows what this version ships. Every skill is a plain folder: it works without the CLI.

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
