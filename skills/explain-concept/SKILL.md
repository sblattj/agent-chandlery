---
name: explain-concept
description: "Explain a design or code concept (a term from a doc, PR, meeting or page) grounded in real code: what it is, why it exists, a real snippet with file:line, the flow, the guards, a one-line simple translation and a mermaid diagram when the flow is complex. Code/docs roots come from arguments, env, or the cwd repo. Triggers on: what is a <term>, explain <term>, what does <term> look like, how does <term> work, where is <term> defined, show me <term> in the code, ELI5 <term>, diagram how <term> flows, what is the retry budget."
---

## More triggers

what is reap grace, what is first writer wins, what is a minted handle, what is a parked run, explain this concept, explain this like the last one, draw me <term>

# explain-concept

Answers "what is X and what does it look like" for a term that lives in prose (docs, artifacts, meetings) and in code under a different name.

## Do this

1. Locate it (read-only). The script bridges the prose name to code identifiers:
   ```bash
   ${SKILL_DIR:-~/.claude/skills/explain-concept}/find-concept.sh "<term>" [code_root] [docs_root] [-a codeAlias ...]
   ```
   Roots: args, else `CODE_ROOT` / `DOCS_ROOT` env, else the cwd git repo (code) and its `docs/` (docs). If the user names no repo and cwd isn't the right one, check the user's agent instructions file (AGENTS.md / CLAUDE.md) in case it names default code/docs roots; otherwise ask. Env: `MAX` (hits per section), `BRIDGE_MAX`, `INCLUDE_TESTS=1`.
   Example: `find-concept.sh "dist-tag" ~/dev/acme-cli ~/dev/acme-cli/docs`.
2. Read the top definition file (its class Javadoc usually holds the canonical example) and the one call site that enforces it. Don't read more unless something's unclear.
3. Answer in this shape, tight:
   - **One-line definition**, then **why it exists** (the constraint that forced it).
   - **What it looks like**: the exact snippet copied from code, with `path:line` and the commit short SHA the script printed.
   - **How it flows**: 3 to 6 numbered steps naming the real classes/endpoints.
   - **Guards** (what stops it misfiring or being abused), only if they exist in the code.
   - **S-T:** (simple translation) one plain-language sentence, built on a single analogy.
   - Mermaid diagram only if the rule below says so.
   - End with a question offering the next step (show tests, run it live, diagram it, publish it).

## Mermaid: when and how

- Add one only when the flow has **3+ actors, an async hop, or a branch** (e.g. signal -> park -> callback -> resume). A single struct or a config value gets no diagram.
- Use `sequenceDiagram` for request/callback flows, `stateDiagram-v2` for lifecycles (PENDING -> RESOLVED / TIMED_OUT), `flowchart LR` for decision rules.
- Keep it to about 10 lines, and use real class names as participants. The terminal shows the fence as text, so keep it readable raw.
- Check for an existing diagram first: if the docs folder keeps diagram sources (d2, PlantUML, mermaid) beside the design docs, reuse their actors and order rather than inventing a different picture.
- If the user wants it rendered, use a renderer that understands mermaid fences (many markdown viewers do), or offer `sketch`.

## Why it's built this way (friction mined)

- **Tool behavior, not repo code (git, GitHub, a CLI)?** There is no file:line to cite, so prove it in a `mktemp -d` scratch repo and quote the real output. That repro caught a wrong claim (GitHub rebase-merge does leak the lower PR's diff into a stacked PR; only a merge commit doesn't). Bound every git call with `</dev/null` and `perl -e 'alarm 30; exec @ARGV'`; an unbounded batch hung 120s.
- **"styled html???" right after a text answer** means they wanted `sketch`. Offer it in the closing question for any flow with 3+ steps.
- **Prose name != code name.** A doc's "retry budget" may never appear in the code: it's `maxAttempts` in `RetryPolicy`, and the Javadoc says "attempt budget". The script pulls backticked identifiers from doc lines that mention the term, then finds where those are declared. It also falls back to the head noun ("budget") in comments.
- **Code wins over docs.** If the docs folder declares code as the authority (the script flags an `AUTHORITY.md`), follow it. Proposal folders often hold many duplicate doc versions (min, v2..v4, slim). The script skips `_superseded/` and `~$` Office lock files. Quote the code snippet, not the doc's paraphrase.
- **zsh eats unquoted globs.** `grep --include=*.java` failed with "no matches found". The script uses quoted `rg --glob`s.
- **Generic doc tokens flood results.** `POST`, `content`, `responses` matched hundreds of OpenAPI lines. The bridge keeps only code-shaped identifiers (camelCase, PascalCase, snake, dotted).
- **Pin the commit.** Feature worktrees move. Cite the short SHA so the answer stays checkable.
- **Configuration needs a worked example.** Show a real default, the environment override, the template expression and the resulting output side by side. Name the tool and command used to produce that output. If another controller interprets it later, show that step separately; rendered text does not establish running behavior.
- **Explain who owns the changing value.** For a controller-managed field, distinguish the configured value, the controller's requested value and the observed state. Do not call a field "initial only" unless its ownership or reconciliation behavior is verified.
- **Decisions and implementation have different evidence.** A fresh user decision can settle the intended target while source text still needs updating. State both facts and preserve unrelated open questions; do not reopen the settled decision merely because an older document differs.
- **Recall/glossary artifacts are shortcuts.** If the docs folder has an HTML recall page or glossary (often a `DATA` object with per-section summaries, file:line pointers and S-T lines), grep it when the docs are ambiguous.
- **Answer shape:** brief, plain wording, an `S-T:` line for jargon, and end the turn with a question offering the next step.

## Related

- `codebase-memory`: graph lookups (callers/callees) when the flow needs tracing beyond one call site.
- `narrated-screenshot`: turn a live demo of the concept into a captioned image.
- `sketch`: when they want a styled local HTML visual (diagrams + comparison table) instead of a text explanation.
