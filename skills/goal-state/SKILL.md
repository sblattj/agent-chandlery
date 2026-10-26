---
name: goal-state
description: "Run a long autonomous push against one goal file: objective, success criteria, a plan of actions that only close with Claim / Evidence / Verdict, a time and turn budget, and a stop hook that keeps the agent going until the goal is achieved with evidence or truly blocked. Triggers on: set a goal, goal prompt, goal file, keep going until done, autonomous run, work until the tests pass, goal status, goal stalled, resume the goal, pause the goal, write a goal for a big push."
---

# goal-state

One file (`.chandlery/goal.json`) holds the goal. The `chandlery goal` CLI is the only writer, so the gates hold: an action can't close without evidence, the goal can't finish with open actions, and the budget stops the loop.

## Do this

```bash
chandlery goal set "Make the parser handle quoted flags" \
  --success "npm test passes" --success "no change to the public API" \
  --constraint "do not touch src/legacy" --max-minutes 240
chandlery goal plan add a1 "write a failing test for quoted flags"
chandlery goal plan add a2 "fix the tokenizer"
chandlery goal status
```

A long handoff goes in a file: `chandlery goal set --brief-file handoff.md` (kept verbatim; the label comes from its first line).

While working:

```bash
chandlery goal act a1 in_progress
chandlery goal act a1 done --claim "test fails on main" --evidence "node --test: 1 fail, expected 'a b'" --verdict pass
chandlery goal act a2 blocked --reason "needs the vendor's spec, not in the repo"
chandlery goal complete --summary "quoted flags parse" --evidence "npm test: 48 pass, 0 fail"
chandlery goal block "the deploy needs a production token I don't have"
```

## Keep the agent going

- **Claude Code:** `chandlery goal hook install` adds a Stop hook to `.claude/settings.json`. Each time the agent tries to stop, the hook counts a turn and, while the goal is active, sends it back with the continuation prompt. It goes quiet once the goal is achieved, blocked or paused.
- **Any other client:** at the end of each turn run `chandlery goal turn`. It prints `continue`, `wrapup` or `stop`, plus the prompt to feed back.
- `chandlery goal prompt` prints the continuation prompt on its own.

## Rules the CLI enforces

- `done` needs `--claim`, `--evidence` and `--verdict pass`. Evidence is something the world produced (command output, file content, an HTTP response), never the agent's own summary. Evidence that can't fail proves nothing.
- `blocked` (action or goal) needs a reason. Block the goal only for something only the human can give: a credential, an irreversible decision, a physical step. An open question is not a blocker; note it and keep working.
- `complete` needs a summary and evidence, and every action must be done-and-verified or blocked with a reason.
- The model has no pause. `pause` is for the human; `resume` opens a fresh budget window.

## Budget and brakes

| Limit | Default | Flag |
|---|---|---|
| Clock | 480 minutes per window | `--max-minutes` |
| Turns | unlimited (0) | `--max-turns` |
| Tokens | unlimited (0); counts only what `goal turn --tokens N` reports | `--max-tokens` |
| Wrap-up | at 80% of the nearest limit: one handoff turn, then pause | (budget.wrapupRatio) |
| Stall | 10 turns with the plan unchanged pauses the goal | `--stall-turns` |

`0` means unlimited (JSON has no Infinity).

## Files

- `.chandlery/goal.json`: the state, written atomically, mode 0600. Add `.chandlery/` to `.gitignore`.
- `.chandlery/goal.json.ledger.jsonl`: one line per event (set, plan, action, turn, pause, resume, blocked, achieved), append-only.
- `chandlery goal validate [file]` checks a hand-edited file against every rule above.
- Override the path with `--file` or `CHANDLERY_GOAL_FILE`.
