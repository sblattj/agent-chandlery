# BASELINE (RED phase)

Skill: going-all-in-or-about-to-claim-done
Method: skill-authoring TDD (RED -> GREEN -> REFACTOR)

## Honesty note on this baseline

This is a **pattern-based baseline**, not a single fresh recorded transcript. The violations below are canonical, repeatedly-observed agent behaviors when given an open-ended "build the whole thing" task. They are corroborated by the kind of always-on agent instructions people write precisely because these failures recur, for example:

- A personal `AGENTS.md`: "Don't stop on a promise; do the next step. Ask the user whether you're done instead of just stopping."
- Session discipline rules: "No completion claims without fresh verification evidence" and "Skipping a step to save time always costs more time."
- A repo's `CLAUDE.md`: "A green summary ... does not establish that tests ran. Report missing evidence."

That is Rung-2 evidence (documents shown) that the target failures are real and matter here. To promote this baseline to Rung 3, run the "Baseline task" below against an agent WITHOUT this skill and confirm the violations reproduce, then record counts.

## Baseline task (for a fresh Rung-3 rerun)

> "Add a new tenant-scoped `POST /widgets` endpoint end to end: spec, handler, persistence with RLS, validation, tests, and wire it into the client. Take it the full distance."

Run an agent on this with no going-all-in-or-about-to-claim-done skill. Record the transcript. Score against the catalog below.

## Violation catalog

Two failure families. The Ambition family (agent does too little) and the Evidence family (agent claims too much). The skill must fix BOTH, because the interesting failure is doing too little while claiming too much.

### Ambition family (fixed by Hard Gate 1)

| # | Violation | Representative exact quote | Rule that kills it |
|---|-----------|---------------------------|--------------------|
| B1 | Scope-shaving to a slice | "I've implemented a basic version of the endpoint. We can extend it with validation and RLS later." | A1 |
| B2 | Stubbing the hard part | "// TODO: wire up persistence" / "return []; // placeholder for now" | A2 |
| B3 | Success-path only | "The endpoint returns the widget on success." (no error, empty, auth, or tenant-mismatch handling) | A3 |
| B4 | Premature hand-back on authorized work | "I've set up the handler. Would you like me to proceed with the tests?" | A4 |
| B5 | Orphan change | "Updated the signature." (callers, generated client, and existing tests left stale and red) | A5 |

### Evidence family (fixed by Hard Gate 2 / the CEV ladder)

| # | Violation | Representative exact quote | Rung it falsely claimed | Rule that kills it |
|---|-----------|---------------------------|-------------------------|--------------------|
| B6 | Weasel word as a result claim | "This should work correctly now." | claims Rung 3, actually Rung 1 | Language cap (weasel list) |
| B7 | Strong-completion word with no artifact | "Done, the feature is complete and passing." (no test output shown) | claims Rung 3, actually Rung 1 | Language cap (strong-completion list) |
| B8 | Mechanical fact with nothing shown | "I've implemented and tested the persistence layer." (no diff, no run) | claims Rung 2, actually Rung 1 | Language cap (mechanical list) |
| B9 | Fabricated / predicted evidence | "Tests pass." written before the tests were ever run | fabricated Rung 3 | "What god mode is NOT" (no fabricated evidence) |
| B10 | Coupling the dials | "It's a large change so I couldn't test all of it, but it should be fine." | uses scope size to excuse skipping evidence | Reconciliation section |

## Baseline frequency (pattern estimate; promote to Rung 3 by rerun)

| Family | Category | Estimated rate (per open-ended build task) |
|--------|----------|--------------------------------------------|
| Ambition | B1-B5 | high: at least one of B1/B4 in most open-ended tasks |
| Evidence | B6-B10 | high: B6/B7 weasel-or-bare "done" is near-ubiquitous |

Label: **Assumption** (pattern-based) until a fresh transcript rerun records real counts. Everything the skill enforces traces to one of B1-B10 above (Traceable criterion satisfied).
