---
name: swarm
description: "Read-only verified fan-out: split a question into atomic units, run them on lean agents (cheapest tier first, a mid tier when a unit can't split, the top tier only for judgment), verify every claim with a skeptic, double-verify with --compare, measure drift between runs. Scales to a whole corpus (one unit file per document). Invoking /swarm IS the Workflow opt-in. Triggers on: /swarm, swarm this, verify these claims, double verify, --compare, fact-check the report, audit read-only, drift between runs, reliability score."
---

# /swarm

**No Workflow tool in your client (OpenCode and others):** don't use this file; read `opencode.md` in this folder and follow it.

Read-only fan-out that returns verified claims. Its sibling `/xx` is the write-capable version, built on the same engine.

Usage: `/swarm <goal> [--compare] [--claims <file>] [--drift <runA> <runB>...] [--runs N]`

Helpers live in `${SKILL_DIR:-~/.claude/skills/swarm}`: `swarm.workflow.js` (the engine) and `swarm.py` (save, drift, ls).

## Do this

1. **Scout inline first** (a few greps or reads) to turn the goal into a work list. Don't fan out blind.
2. **Decompose into units**, making each one as small as possible:
   - `tier: haiku` is the default. One file, one ticket or one question per unit, answerable with shell reads.
   - `tier: sonnet` for a unit that can't be split without losing context (cross-file reasoning, a long diff).
   - `tier: opus` only for judgment that shouldn't be split (design calls, ambiguous intent). It's not banned, just last.
   - `needs_mcp: true` only when the unit needs MCP (a tracker MCP, a browser, a transcript server). It runs as `general-purpose`; everything else runs on `lean` (a shell + file tools agent type, about 10k vs 43k start tokens). If your client has no `lean` agent, define one or change `agentType` in the script.
   - **Big fan-outs: one file per unit.** Inline prompts for 60 units came to 97KB and the Workflow call would not take them. Write the shared rules once (`_INSTRUCTIONS.md`), one input file per unit (`<id>.json`), and keep each `prompt` to one line: "Read /abs/_INSTRUCTIONS.md, then /abs/<id>.json". Same fix for 50 reconcile units (32KB). `swarm-unit-pack` does this for you.
3. **Run it** (the Workflow tool wants an absolute path: expand `~` to your home directory):
   ```
   Workflow({ scriptPath: "<home>/.claude/skills/swarm/swarm.workflow.js",
     args: { goal, mode: "read", compare: <--compare given>,
             units: [{ id, prompt, tier, needs_mcp? }] } })
   ```
   For verify-only (fact-checking an existing report or list), pass `claims: [{ claim, evidence, key? }]` instead of `units`.
   Optional args: `verify_tier` (default haiku), `compare_tier` (default the other of haiku/sonnet), `synth: false` to skip the rollup.
4. **Save the run, then report:**
   - `python3 ${SKILL_DIR:-~/.claude/skills/swarm}/swarm.py save <runId> --slug <topic>`
   - Report `stats` plus `summary`. With `--compare`, list every disagreement: a single verifier's "confirmed" is weaker than a double-confirmed one.
5. **Drift (reliability):**
   - Rerun the same script and args, or pass `--runs N` to launch N runs. Each rerun needs a nonce in `goal` (for example `goal + " [run 2]"`), or resume caching replays run 1.
   - Then run `swarm.py drift <runA> <runB> [...]`.
   - It reports claim overlap (Jaccard), verdict agreement on matched claims, `reliability = overlap x agreement`, the flips, and the claims found in only one run.
   - It works on any workflow runId, swarm or not, by falling back to journal parsing.

`swarm.py ls [slug]` lists saved runs in `${SWARM_STATE:-~/.local/state/swarm}/`. Claude Code transcripts are read from `$CLAUDE_CONFIG_DIR/projects` (default `~/.claude/projects`).

## Why it's built this way (friction mined)

- **Claims need evidence, and verifiers default to "unclear".** In a backlog gap audit, the cheap-tier finders were mostly right, but the skeptic pass caught done-vs-open errors (a work item marked Done while part of it was still open). Never trust a finder's verdict unchecked.
- **`--compare` uses a different tier** (haiku then sonnet by default) so the two verifiers don't share the same blind spot. Disagreements are where a human should look.
- **The read-only guarantee is enforced by the prompt only.** `lean` still has Bash, Edit and Write. If a run must be provably read-only, point it at a throwaway clone or check `git status` afterwards.
- **Verifiers get the goal as context.** When the verify prompt had only claim + evidence, relative paths like `diffs/x.diff` were unfindable and 97 of 165 verdicts came back "unclear". Put absolute input paths in `goal`; it goes to every verifier.
- **Pin the cheap tier to an exact model id.** The script maps `haiku` to `claude-haiku-5-5` because the bare `haiku` alias once resolved to an older model than intended. Edit `MODEL()` in the script to whatever exact id you want; don't trust aliases for tiering.
- **Pipeline, not barriers.** Each unit's claims verify as soon as that unit finishes.
- **Workflow results get truncated in the tool output.** The full return is in `tasks/<id>.output`, and per-agent results are in `subagents/workflows/<runId>/journal.jsonl` under the session's project dir. `swarm.py` reads both. `big-tool-result` helps read them.
- **Drift matching** goes by exact `key`, then normalized text, then fuzzy text at 0.75 or above (`--threshold`). Give claims stable keys (`file:line`, `#1234`) so reruns line up.
- **Keep token counts from the output** (`totalTokens`) so you can size the next run.
- **`--compare` fold rule.** A claim is refuted only when both verifiers refute it. The cheap verifier refuting a side detail while the mid verifier confirms is a disagreement to flag, not a refute; folding on either refute pushed 7 of 57 reconcile units to not_checkable until fixed.
- **A lone refute with a cited file can be the right one.** A docs claim ("X is not documented anywhere") got refuted by one verifier citing `docs/...md:298` while the other confirmed after grepping the wrong branch. Grep the cited path yourself before keeping "confirmed"; absence claims are the weakest kind.
- **Pull the non-double-confirmed rows** from `tasks/<id>.output`: the JSON can be nested under `result` strings, so unwrap until `claims` exists, then print rows where `verdict` or `verdict2` is not `confirmed` (this beat reading the 30KB truncated inline result).
- **Read the comparer's `reason2`.** It cites counterexamples the first pass missed: three "not checkable" commitments turned out to have chat posts proving them done. Grep the cited file yourself, then apply it as a named override, never silently.
- **Scale seen on a 235-document corpus:** 60 units with --compare ran 372 agents and about 5.9M tokens; 50 reconcile units ran 164 agents and about 3.0M tokens. Say that up front before a big run over a corpus.

## Related

- `xx`: same engine with `mode: "write"`.
- `swarm-prompt`: writes a fan-out prompt but doesn't run it.
- `forge-skill`: harden this skill after real runs.
- `swarm-unit-pack`: pack 50+ units into per-unit files so the Workflow args stay small.
- `big-tool-result`: read the full `tasks/<id>.output` when the inline result is truncated.

## Live validation

- **Setup:** 5 claims from a gap report pinned to a repo commit, with one claim planted false. Two runs, both with `--compare`.
- **Result:** each run used 11 agents and about 138k tokens and took 36 to 56s. Both runs matched ground truth 5/5 and refuted the planted claim. Drift between the runs was 100%.
- **Pin claims to a commit SHA.** Another session was editing the same branch at the same time, and an unpinned claim would read as drift when it's really a code change.
- **Synthesis prose drifted while the data didn't.** Run 2's rollup said "3 confirmed" when stats said 4. The fix is that stats now go into the synth prompt as fixed counts. Trust `stats` and `claims`, never the prose.
- **zsh gotcha when grading by hand:** `$C:core/...` is parsed as the `:c` history modifier, so write `"${C}:path"`.
