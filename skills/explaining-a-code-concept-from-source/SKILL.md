---
name: explaining-a-code-concept-from-source
description: "Explain a design or code concept (a term from a doc, PR, meeting or page) grounded in real code: definition, why it exists, a real snippet with file:line and commit, the flow, the guards, an S-T line, and a hand-drawn SVG when the flow is complex. Triggers on: explain-concept (old name), what is a <term>, explain <term>, how does <term> work, where is <term> defined, show me <term> in the code, ELI5 <term>, diagram how <term> flows."
---

## More triggers

explain-code-concept-from-source-with-snippets-and-handdrawn-svg (old name), what is reap grace, what is a parked run, explain this like the last one, draw me <term>

# explaining-a-code-concept-from-source

1. Bridge the prose name to code identifiers (read-only): `${CLAUDE_SKILL_DIR:-${SKILL_DIR:-~/.claude/skills/explaining-a-code-concept-from-source}}/find-concept.sh "<term>" [code_root] [docs_root] [-a codeAlias ...]`. Roots: args, else `CODE_ROOT` / `DOCS_ROOT`, else the cwd repo and its `docs/`; the user's agent instructions may name defaults. Env: `MAX`, `BRIDGE_MAX`, `INCLUDE_TESTS=1`.
2. Read the top definition file and the one call site that enforces it.
3. Answer tight: one-line definition, why it exists, the exact snippet with `path:line` and the short SHA the script printed, a 3-6 step flow naming real classes, guards (only if in code), an `S-T:` line, then a closing question offering the next step (tests, run it live, a styled page).

## Diagram

- Only for 3+ actors, an async hop or a branch. A self-contained `.svg` with inline styles, real class names as labels, about 10 elements; hand-drawn feel from strokes, never handwritten fonts. Save it to `$SKETCH_DIR/<topic>/` if set, else the repo's gitignored `tmp/`, else `~/sketches/`, and print the path; keep the numbered flow in the text.
- Reuse existing diagram sources (d2, PlantUML, mermaid) in the docs for actors and order.

## Gotchas

- **Prose name != code name.** A doc's "retry budget" may be `maxAttempts` in code. The script pulls backticked identifiers from doc lines that mention the term and keeps only code-shaped ones (generic tokens like `POST` flood results).
- **Code wins over docs.** Follow an `AUTHORITY.md` if the script flags one; it skips `_superseded/` and `~$` lock files. Quote code, not the doc's paraphrase.
- **Tool behavior (git, GitHub, a CLI) has no file:line:** prove it in a `mktemp -d` scratch repo and quote real output, every git call bounded with `</dev/null` and `perl -e 'alarm 30; exec @ARGV'`.
- **Config needs a worked example:** real default, env override, template expression and rendered output side by side; rendered text isn't running behavior. For controller-managed fields, separate configured, requested and observed values.
- **"styled html???" after a text answer** means they wanted `building-a-local-html-visual-explainer`.

## Related

- `building-a-local-html-visual-explainer`: a styled local HTML page instead of a text answer.
- `querying-the-codebase-memory-graph`: callers/callees beyond one call site.
