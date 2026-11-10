# agent-chandlery

**35 agent skills and a goal-state loop for Claude Code, Kiro and Codex.** Fan-out with verification, evidence-first PRs, stacked PRs, skill hygiene, and a goal file that keeps an agent working until the job is done with proof.

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
| [`goal-file-autonomous-run-until-evidence`](skills/goal-file-autonomous-run-until-evidence/SKILL.md) (alias `goal-state`) | One goal file per project: objective, success criteria, a plan whose actions close only with Claim / Evidence / Verdict, a clock and turn budget, and a stop hook that keeps the agent going. |
| [`going-all-in-or-about-to-claim-done`](skills/going-all-in-or-about-to-claim-done/SKILL.md) | Maximal-ambition delivery gated by an evidence ladder before anything is called done. |
| [`fanning-out-a-verified-read-only-swarm`](skills/fanning-out-a-verified-read-only-swarm/SKILL.md) (alias `swarm`) | Read-only fan-out: split a question into small units, run them on cheap agents, verify every claim. |
| [`fanning-out-parallel-writers-with-verified-changes`](skills/fanning-out-parallel-writers-with-verified-changes/SKILL.md) (alias `xx`) | The write-capable swarm: fan out implementation units, verify, integrate. |
| [`writing-an-orchestrator-fan-out-prompt`](skills/writing-an-orchestrator-fan-out-prompt/SKILL.md) (alias `swarm-prompt`) | Write a ready-to-hand-off fan-out prompt for an orchestrator agent. |
| [`fitting-a-50-plus-task-fan-out-under-workflow-limits`](skills/fitting-a-50-plus-task-fan-out-under-workflow-limits/SKILL.md) (alias `swarm-unit-pack`) | Pack a 50+ unit fan-out into per-unit files so the workflow args stay small. |
| [`reading-overflowed-tool-output`](skills/reading-overflowed-tool-output/SKILL.md) (alias `big-tool-result`) | Read a tool result or workflow output that overflowed the context. |

**Pull requests**

| Skill | What it does |
|---|---|
| [`proving-a-bugfix-pr-red-to-green`](skills/proving-a-bugfix-pr-red-to-green/SKILL.md) (alias `pr-ab-evidence`) | Red-to-green A/B proof that a bug-fix PR fixes the bug: same test, base vs fix. |
| [`walking-a-pr-logic-diff-in-request-order`](skills/walking-a-pr-logic-diff-in-request-order/SKILL.md) (alias `pr-logic-trail`) | A logic-only HTML walkthrough of a PR, ordered by the path a request travels. |
| [`checking-what-my-github-prs-need-and-from-whom`](skills/checking-what-my-github-prs-need-and-from-whom/SKILL.md) (aliases `pr-activity-since-push`, `pr-approval-gate`) | What each open PR needs and from whom: activity since your last push, CI, conflicts, CODEOWNERS gaps, draft, behind. |
| [`rereviewing-a-github-pr-after-reply`](skills/rereviewing-a-github-pr-after-reply/SKILL.md) (alias `pr-rereview-after-reply`) | Re-review after the author replies: check every claimed fix is really on the head. |
| [`resolve-pr-threads-and-conflicts-and-merge`](skills/resolve-pr-threads-and-conflicts-and-merge/SKILL.md) | Land an approved PR: answer and resolve threads, fix conflicts, wait for CI, merge. |
| [`opening-a-stacked-pr-sequence`](skills/opening-a-stacked-pr-sequence/SKILL.md) | Open dependent PRs in the right order with the right bases. |
| [`landing-stacked-github-prs`](skills/landing-stacked-github-prs/SKILL.md) (alias `landing-stacked-prs`) | Land a stack of PRs one layer at a time. |
| [`scrub-and-open-issue`](skills/scrub-and-open-issue/SKILL.md) | Scrub internal identifiers from an issue, then file it as the repo owner, never a work account. |

**Skills and context**

| Skill | What it does |
|---|---|
| [`forge-skill-from-session-friction`](skills/forge-skill-from-session-friction/SKILL.md) | Turn what just happened in a session into a reusable skill by mining the friction. |
| [`auditing-skill-context-cost-from-session-logs`](skills/auditing-skill-context-cost-from-session-logs/SKILL.md) (alias `skill-diet-audit`) | Per-skill usage vs context cost from session logs, with trim suggestions. |
| [`ab-testing-whether-skills-still-trigger`](skills/ab-testing-whether-skills-still-trigger/SKILL.md) (alias `skill-trigger-ab`) | A/B whether skills still fire after changing their descriptions or overrides. |
| [`building-a-prompt-to-skill-hint-hook`](skills/building-a-prompt-to-skill-hint-hook/SKILL.md) (alias `skill-hint-hook`) | A prompt hook that ranks skills against the prompt and hints the best match. |
| [`measuring-claude-session-start-tokens`](skills/measuring-claude-session-start-tokens/SKILL.md) (alias `real-start-tokens`) | The real starting context of recent sessions, split by block. |
| [`measuring-what-a-kiro-agent-loads-into-context`](skills/measuring-what-a-kiro-agent-loads-into-context/SKILL.md) (alias `kiro-context-probe`) | What a Kiro CLI agent actually loads into context. |
| [`finding-claude-session-gating-logic`](skills/finding-claude-session-gating-logic/SKILL.md) | Why a Claude Code feature is refused: find the gate in the installed bundle. |
| [`watching-another-claude-session-live`](skills/watching-another-claude-session-live/SKILL.md) (alias `watch-claude-session`) | Find and follow another session's transcript. |
| [`relaying-a-go-ahead-to-another-claude-session`](skills/relaying-a-go-ahead-to-another-claude-session/SKILL.md) (alias `peer-relay`) | Relay a go-ahead to another agent session without sending a stale one. |

**Code understanding and visuals**

| Skill | What it does |
|---|---|
| [`querying-the-codebase-memory-graph`](skills/querying-the-codebase-memory-graph/SKILL.md) (alias `codebase-memory`) | Structural code questions over a code knowledge graph: callers, call chains, architecture. |
| [`indexing-a-repo-into-codebase-memory`](skills/indexing-a-repo-into-codebase-memory/SKILL.md) (alias `cbm-index`) | Index a repo into that graph the right way: survey, fitted ignore file, full mode. |
| [`explain-code-concept-from-source-with-snippets-and-handdrawn-svg`](skills/explain-code-concept-from-source-with-snippets-and-handdrawn-svg/SKILL.md) | Explain a code concept grounded in real snippets, with a diagram when it helps. |
| [`building-a-local-html-visual-explainer`](skills/building-a-local-html-visual-explainer/SKILL.md) (alias `sketch-local-html-visual-explainer`, `sketch`) | A styled local HTML explainer with hand-drawn SVG diagrams, linted in light and dark. |
| [`making-a-narrated-ab-screenshot`](skills/making-a-narrated-ab-screenshot/SKILL.md) (alias `narrated-screenshot`) | A self-explaining A/B screenshot with captions and a verdict. |
| [`recording-a-narrated-ab-proof-video`](skills/recording-a-narrated-ab-proof-video/SKILL.md) (alias `narrated-ab-video`) | A narrated A/B proof video from recorded browser runs. |
| [`diffing-web-app-aria-snapshots-a-vs-b`](skills/diffing-web-app-aria-snapshots-a-vs-b/SKILL.md) (alias `cdp-route-snapshots`) | ARIA snapshots of a list of routes through a CDP browser. |

**Reporting and environments**

| Skill | What it does |
|---|---|
| [`summarizing-what-someone-shipped-from-git-log`](skills/summarizing-what-someone-shipped-from-git-log/SKILL.md) (alias `work-overview-from-git-log`, `work-overview`) | A narrative overview of what one person shipped across local repos. |
| [`snapshotting-shipped-work-since-a-date`](skills/snapshotting-shipped-work-since-a-date/SKILL.md) (alias `evidence-dump`) | Dump shipped-work evidence (PRs, commits) into one folder for reconciling. |
| [`diagnosing-macos-disk-cpu-and-memory-usage`](skills/diagnosing-macos-disk-cpu-and-memory-usage/SKILL.md) | Read-only macOS disk, CPU and memory diagnosis with bounded scans, retained partial results and APFS allocation caveats. |
| [`reproducing-a-windows-bug-in-a-fusion-vm-from-a-mac`](skills/reproducing-a-windows-bug-in-a-fusion-vm-from-a-mac/SKILL.md) (alias `windows-vm-repro`) | Reproduce Windows-only bugs from a Mac through a Parallels VM. |

`chandlery list` shows what this version ships. Every skill is a plain folder: it works without the CLI.

## Install

Not on the npm registry yet: run it straight from GitHub with `npx github:sblattj/agent-chandlery`, or clone and `npm link` to get `chandlery` on your PATH.

**Per project** (copies, so the repo carries them):

```bash
npx github:sblattj/agent-chandlery install --client claude              # .claude/skills/
npx github:sblattj/agent-chandlery install --client kiro                # .kiro/skills/
npx github:sblattj/agent-chandlery install --client codex               # .agents/skills/
npx github:sblattj/agent-chandlery install --only goal-state --dry-run   # old short names still work as aliases
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

State lives in `.chandlery/goal.json` (atomic writes, mode 0600) with an append-only ledger beside it. Full reference: [skills/goal-file-autonomous-run-until-evidence/SKILL.md](skills/goal-file-autonomous-run-until-evidence/SKILL.md).

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
