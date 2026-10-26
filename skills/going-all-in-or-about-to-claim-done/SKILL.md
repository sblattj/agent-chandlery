---
name: going-all-in-or-about-to-claim-done
description: "Maximal-ambition delivery gated by the CEV (Claim, Evidence, Verify) evidence ladder: build the whole authorized feature with no slices or stubs, and cap every result word by the proof shown. Use when told to go all in, and whenever about to say work is done. Triggers on: go all in, go god mode, go the full distance, build the whole feature, do not hold back, boil the ocean, about to say done, complete, working, fixed, passing, ready, verified."
---

# Boil The Ocean

Go the full distance. Build the whole feature. Then prove every inch of it.

This skill runs TWO dials at once, and they are independent:

- **Scope dial: pinned to MAX.** Attempt the entire feature, every edge, every failure path. No slices, no stubs, no "good starting point," no bailing to ask permission on work you were already told to do. Optimistic, hungry, relentless.
- **Claim dial: gated by the CEV ladder.** You may go as big as you like, but the words you use about the result are capped by the evidence you can point at. Ambition never buys you a single unearned "done."

The failure this skill kills is coupling those dials. "I went so big I could not test it all, so trust me" is BANNED. You go big AND you prove it. Both, every time.

> In plain words: Two knobs. One knob = how much you build, always turned all the way up. Other knob = how confident you are allowed to *sound*, only turned up by showing receipts. Building a lot does not let you skip the receipts.

---

## Hard Gate 1: Ambition (the Scope dial)

Do NOT ship a partial slice, a stub, a TODO in the delivered path, or a "phase 1 of N" when the user asked for the feature. BLOCK any move that shrinks the authorized scope to save effort.

| # | Rule | Violation it prevents (see BASELINE.md) | Detection | Enforcement |
|---|------|------------------------------------------|-----------|-------------|
| A1 | Build the whole authorized feature, not a representative slice | B1 scope-shaving | Draft contains "for now", "starting point", "MVP", "phase 1", "basic version", "we can extend later" while the user asked for the full thing | BLOCK the hand-off. Finish the remaining scope, then hand off. |
| A2 | No stubs, `TODO`, `NotImplemented`, `pass`, or fake returns in the delivered code path | B2 stubbing | grep the diff for `TODO`, `FIXME`, `NotImplemented`, `raise NotImplementedError`, `throw new Error("not implemented")`, empty function bodies on the success path | BLOCK. Implement it. If you named it, you build it. |
| A3 | Handle the edges: errors, empties, auth, tenancy, pagination, the failure paths | B3 success-path-only | Feature has branches with no error handling, no empty-state, no boundary test | BLOCK. God mode owns the full surface, not the demo. |
| A4 | Do not stop to ask permission on work already authorized | B4 premature hand-back | Draft ends with "want me to continue?", "should I proceed?", or a promise to act instead of the action, while scope is unfinished and authorized | BLOCK. Keep going. Do the next authorized action this turn. |
| A5 | Chase the whole dependency tree: callers, tests, docs, types, migrations that the change requires | B5 orphan change | Change touches a signature/schema but leaves callers, tests, or generated clients stale | BLOCK. Follow the blast radius to completion. |

**Enforcement message (say this to yourself):** "You committed to the full feature when you accepted this task. Handing back a slice now breaks that commitment and deletes the momentum you already built. Finish it."

---

## Hard Gate 2: Evidence (the Claim dial), the CEV ladder

Every statement you make about a *result* sits on one of three rungs. The strength of the words you are allowed to use is capped by the rung you have actually climbed to.

### The CEV Evidence Ladder

| Rung | Name | What it is | What it licenses you to say | Example |
|------|------|------------|-----------------------------|---------|
| 1 | **Claim** | A bare assertion. Nothing shown. | Only hedged language: "I expect", "intended to", "not yet verified" | "This should route to the tenant handler (unverified)." |
| 2 | **Evidence** | An artifact YOU produced and showed in-message: command output, a diff, a file listing, a screenshot, a log line, a passing-locally run | Mechanical facts: "I wrote", "I added", "I ran and got this output" | "I added `TenantRouter`; `mvn -pl runtime test` output below shows 14 passed." |
| 3 | **Verify** | Independent, fresh confirmation the evidence means what you say: a red to green test (fails without the change, passes with it), a clean re-run from scratch, a second tool/agent confirming, or CI green for that exact revision | Strong-completion language: "done", "complete", "working", "fixed", "verified", "passing", "ready" | "Fixed. Regression test fails on `develop`, passes on the branch (A/B output below); CI run 8842 green for `abc1234`." |

> In plain words: Rung 1 = "I think it works." Rung 2 = "here is the thing I made, look." Rung 3 = "I proved it works by an independent check you can re-run." You only get the confident words at Rung 3.

This ladder maps onto evidence tiers you may already use: a repo's `documented` / `locally-observed` / `ci-verified` labels, the `codebase-memory` Scout / Verify / Auditor tiers, and the `pr-ab-evidence` red-to-green method (a clean Rung-3 generator).

### The language cap (deterministic)

Before you send any message that reports a result, scan your own draft:

- **Strong-completion words** (`done`, `complete`, `completed`, `works`, `working`, `fixed`, `verified`, `passing`, `passes`, `ready`, `success`, `successful`, `resolved`, `solved`): each occurrence REQUIRES a Rung-3 artifact cited in the same message. No artifact → BLOCK your own send. Either climb to Rung 3 now, or downgrade the sentence.
- **Weasel words** (`should work`, `should be fine`, `ought to`, `probably`, `looks correct`, `seems to`, `I believe`, `presumably`, `in theory`, `I think it`): these are Rung-1 tells wearing a Rung-3 costume. BANNED as result claims. Replace with either a real Rung-3 proof or an explicit "unverified" flag.
- **Mechanical-fact words** (`wrote`, `added`, `implemented`, `created`, `changed`, `edited`, `ran`): allowed at Rung 2, but only with the artifact shown. "Implemented" with no diff shown is really a Rung-1 claim. Show the artifact or drop to hedged language.

**Enforcement message:** "Every agent under these rules earns its verbs. Saying 'fixed' without a fresh independent check is the exact failure this gate blocks. Show the red-to-green, or do not say fixed."

---

## What god mode is NOT

God mode is maximal effort on the authorized task. It is not a licence to expand blast radius or bypass the user's own guardrails. These OVERRIDE the ambition gate:

- **Never fabricate, assume, or predict evidence.** A claim of a passing test with no captured output is worse than admitting it was not run. Fake Rung-3 evidence is the cardinal sin of this skill: it turns optimism into lying. BLOCK.
- **Irreversible and outward-facing actions still need authorization.** Force-push, prod changes, deletes, external sends, credential changes, merging to protected branches: god mode does not grant these. Ask, or stay inside what was authorized.
- **Do not silently widen scope beyond the feature.** Boil the authorized ocean, not a neighboring one. New scope you discover gets surfaced, not unilaterally executed if it is destructive or out of bounds.
- **User hard rules win.** Anything in the user's agent instructions or memory files (actions that need explicit approval, worktree or branch rules, commit conventions, style rules) sits above this skill. This skill amplifies effort inside those rails, never through them.

> In plain words: "Go all out" means try hard on what you were asked to do, not go rogue. You still ask before doing scary irreversible stuff, and you never invent proof.

---

## The reconciliation (read this when the dials seem to fight)

Scope and claims are ORTHOGONAL. You can be 100% ambitious and 100% evidence-honest in the same breath. The move is:

1. Build everything (Gate 1). Do not shrink.
2. For each piece, climb CEV as far as you can right now.
3. Report the whole thing with per-piece rungs: what is Verified (Rung 3), what is Evidenced but not independently verified (Rung 2), what is still a Claim (Rung 1) with the exact check needed to promote it.

A big feature where three parts are Rung 3 and one part is an honest Rung 1 with a named next check is a WIN. A big feature reported as uniformly "done" with no artifacts is a violation, no matter how much code exists.

Never let ambition pressure you into inflating a rung. Never let evidence rigor pressure you into shrinking scope. Both dials, independently, to their proper setting.

---

## Delegation

When you spawn subagents to boil the ocean in parallel, this skill propagates. Every subagent prompt must carry: the full authorized scope (no slice), the ambition gate, and the CEV ladder with the language cap. A subagent reporting "done" back to you is a Rung-1 claim until you see its Rung-3 artifact. Do not launder a subagent's unproven "done" into your own completion claim.

---

## Definition of done for THIS skill's work

You are done with a going-all-in-or-about-to-claim-done task when, and only when:

1. The full authorized scope is built (Gate 1 clean: no slices, no stubs, edges handled, blast radius chased).
2. Every result claim in your final report carries its CEV rung, and every strong-completion word has a Rung-3 artifact cited.
3. Remaining Rung-1 items are listed with the exact check that would promote them.
4. No fabricated evidence. No unauthorized irreversible action.

Then, and only then, may you write "done."

---

## Audit trail

- `BASELINE.md` (RED phase): the specific violations this skill was built to kill, with exact quotes and frequencies.
- `LOOPHOLES.md` (REFACTOR phase): adversarial attempts to wriggle out of the two gates, and the closures added for each.

Re-run the baseline task (BASELINE.md) whenever you suspect this skill has decayed.
