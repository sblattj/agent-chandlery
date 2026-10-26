---
name: xx
description: "Write-capable /swarm: fan out implementation units on lean agents (cheapest tier first, mid or top tier only for units that can't split) with explicit file ownership and worktrees, then verify every change claim (diff plus tests) with skeptics, optionally --compare. Invoking /xx IS the Workflow opt-in. Triggers on: /xx, swarm and fix, fan out the fixes, parallel writers, apply these changes with agents, multi-agent implement, xx --compare."
---

# /xx

Same engine as `/swarm` (`${SKILL_DIR:-~/.claude/skills/swarm}/swarm.workflow.js`, from the `swarm` skill), run with `mode: "write"`. Usage: `/xx <goal> [--compare]`.

## Do this

1. **Scout inline** and split the work into units the same way as `/swarm`: the cheap tier by default, `sonnet` or `opus` only for units that can't be split.
2. **Declare the workspace before launching.** Pick one strategy:
   - One git worktree per writer (for example a sibling dir like `../<repo>-<suffix>`), branched from the repo's integration branch. Take that branch from the repo's own rules or the user's agent instructions file (AGENTS.md / CLAUDE.md) if it names one; otherwise infer it from the cwd and git remote, or ask. Create the worktrees yourself, then pass `worktree: "<abs path>"`.
   - Or one shared task worktree with non-overlapping `owns`.
   - `isolate: true` asks the harness for a throwaway worktree. It's expensive, so use it only when you have nothing else.
3. **Give every unit `owns: [abs paths, including new tests]`.**
   - The script gives each writer the full sibling ownership map plus the concurrent-edit notice.
   - If any `owns` overlap, the script runs writers one at a time, on purpose.
   - Shared files, lockfiles and generated outputs get a single owner.
4. **Run it** (absolute path: expand `~` to your home directory):
   ```
   Workflow({ scriptPath: "<home>/.claude/skills/swarm/swarm.workflow.js",
     args: { goal, mode: "write", compare, units: [{ id, prompt, tier, owns, worktree, needs_mcp? }] } })
   ```
   Writers report each change and each test result as a claim with evidence. Skeptics re-run the reads and check the diffs.
5. **Integrate:**
   - Review each worktree's diff and run the combined tests yourself, bounding long runs with `perl -e 'alarm N; exec @ARGV'`.
   - Then commit with the tracker ticket id (if the repo uses one) and whatever attribution line the repo expects.
   - Push only where the repo's rules allow it. Cut PRs the way the repo does (a stacked sequence fits `opening-a-stacked-pr-sequence`).
   - Writers never push, merge or post.
6. Save the run with `python3 ${SKILL_DIR:-~/.claude/skills/swarm}/swarm.py save <runId> --slug <topic>`. Measure drift with `swarm.py drift`, the same as in `/swarm`.

## Why it's built this way (friction mined)

- **Ownership must be written into each prompt.** Subagents don't inherit the parent's context. Unbounded or overlapping ownership caused clobbered edits in earlier fan-outs, so overlap forces sequential runs.
- **Don't edit a worktree while its test suite runs.** A hermetic test runner that checks for stray changes counts your own edit as a leak. Run verification only after the writers finish.
- **Never `git stash -u` in a shared main worktree.** Other sessions work there. Use separate worktrees for heavy writes.
- **lean has no MCP.** A unit that has to touch a tracker through MCP needs `needs_mcp: true`. Prefer the tracker's REST API with a CLI-issued token in Bash, which works fine on lean.

## Related

- `swarm`: read-only mode, the drift tooling and the full rationale.
- `opening-a-stacked-pr-sequence`, `landing-stacked-prs`: turn the integrated result into PRs.
