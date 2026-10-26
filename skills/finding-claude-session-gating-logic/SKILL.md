---
name: finding-claude-session-gating-logic
description: "Explain why a Claude Code CLI feature is refused or disabled when the docs don't cover it, by searching the installed binary's bundled JS for the error text and the predicate behind it. Triggers on: why does claude code say, what disables this in claude code, find the condition behind this claude error, search the claude binary, undocumented claude code error, why is session persistence disabled, Cannot background, Cannot open agents."
---

# Find the gating logic behind a Claude Code message

## Do this

```zsh
S=${SKILL_DIR:-~/.claude/skills/finding-claude-session-gating-logic}/cc-grep.py
$S 'Cannot background'     # the message in context: shows the guard call, e.g. if(Fa())return h("Cannot background ...")
$S -f Fa                    # the guard's body; minified names repeat across bundles, read every hit
$S -f dFn                   # follow the chain until it hits env vars / settings
```
`CLAUDE_BIN` overrides the binary (default: newest `~/.local/share/claude/versions/*`). `strings` output is cached in `/tmp/cc-strings-<version>.txt`.

Check the docs first (search them for the exact message, with a docs MCP tool if you have one); go to the binary when they don't name the cause. Then confirm on the live process: `ps eww -o command= -p <pid>` shows the env the guard reads.

## Why it's built this way (friction mined)

- **`grep -o '.{0,300}msg.{0,80}'` on the binary dies**: ugrep `exceeds complexity limits`. Dump `strings` once and slice in Python.
- **Minified names collide.** `function Fa()` matched 3 unrelated functions; the right one was the one returning a reason-check (`dFn()!==null`). Print all hits and pick by content.
- **Worked example (2.1.302):** `Cannot background` -> `Fa()` -> `dFn()` -> reasons `test_env`, `explicit_disable` (`--no-session-persistence`), `skip_prompt_history` (`CLAUDE_CODE_SKIP_PROMPT_HISTORY`), `nested_marker` (`SJe()`: `CLAUDE_CODE_CHILD_SESSION` set, overridable with `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE`). The live process env had `CLAUDE_CODE_CHILD_SESSION=1`.
- Code is version-specific: name the version when you report a finding.

## Related

- `watch-claude-session`: read the transcript of the session that hit the message.
- The Claude Code docs (or a docs-search tool, if you have one): documented behavior, checked first.
