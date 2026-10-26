# LOOPHOLES (REFACTOR phase)

Skill: going-all-in-or-about-to-claim-done
Adversarial tests run against the two gates. Each loophole found gets a closure that is already reflected in SKILL.md.

The skill-authoring framework requires at least 3 loophole tests. Six are recorded below.

## L1: Synonym attack on the language cap

**Attack:** Dodge the strong-completion word list with synonyms. "Done" -> "wrapped up", "shipped", "good to go", "all set", "sorted", "handled".

**Result:** The bare word list would miss these.

**Closure:** The language cap is defined by *rung*, not only by a fixed word list. Any phrase that asserts a finished result is a Rung-3 claim and needs a Rung-3 artifact, whatever the vocabulary. The word list in SKILL.md is a floor of examples, not the ceiling. Added the standing rule: "each occurrence REQUIRES a Rung-3 artifact ... Either climb to Rung 3 now, or downgrade the sentence" applies to any completion-flavored phrasing.

## L2: Spirit vs letter: the trivial test

**Attack:** Satisfy Rung 3 with a test that cannot fail. `assert True`, or a test that asserts the mock returns the mock. Technically "a passing test."

**Result:** Rung 3 reached on paper, not in reality.

**Closure:** Rung 3 is defined as a test that **fails without the change and passes with it** (red to green), or a clean-room re-run, or CI green for the exact revision. A test that passes on the unmodified base is not Rung-3 evidence for the change. The `pr-ab-evidence` red-to-green method is named as the canonical Rung-3 generator precisely to block the always-green test.

## L3: Scope reduction: "the full distance for the part I chose"

**Attack:** Redefine "the whole feature" narrowly, then boil that small ocean completely and claim Gate 1 satisfied. "I fully implemented the read path" when the task was read and write.

**Result:** Gate 1 technically clean against a shrunken definition.

**Closure:** Gate 1 anchors scope to "the authorized feature" as the user framed it, and A5 (blast radius) forces chasing callers/tests/docs/migrations the change requires. Rule A1 detection includes "phase 1" and "basic version" framing. The Definition of done requires "the full authorized scope," not a self-selected subset. Scope narrowing is surfaced to the user, not performed silently.

## L4: Temporal evasion: claim now, prove later

**Attack:** Write "fixed, tests pass" in the message, intending to actually run the tests afterward, or predicting they will pass.

**Result:** Fabricated Rung 3 (this is B9).

**Closure:** The language cap runs on the *draft before send*: "Before you send any message that reports a result, scan your own draft." The artifact must be cited **in the same message**. "What god mode is NOT" bans fabricated or predicted evidence outright and calls it the cardinal sin. No future-tense proof counts.

## L5: Delegation dodge: launder a subagent's "done"

**Attack:** Spawn a subagent, get back "done, complete," and repeat it upward as your own completion claim without seeing the artifact.

**Result:** Rung-1 claim relabeled as Rung 3 across an agent boundary.

**Closure:** The Delegation section: "A subagent reporting 'done' back to you is a Rung-1 claim until you see its Rung-3 artifact. Do not launder a subagent's unproven 'done' into your own completion claim." The gate propagates into every subagent prompt.

## L6: Coupling the dials: use ambition to excuse missing evidence

**Attack:** "It's a huge change, boiling the whole ocean, so exhaustive verification is impractical; trust the volume." This is the exact failure the skill exists to kill (B10).

**Result:** Big scope used as currency to buy unearned confidence.

**Closure:** The Reconciliation section declares the dials orthogonal and gives the correct move: report per-piece rungs, mark honest Rung-1 items with the exact promoting check. Explicit line: "A big feature reported as uniformly 'done' with no artifacts is a violation, no matter how much code exists." and "Never let ambition pressure you into inflating a rung."

## Quality criteria check (skill-authoring)

| Criterion | Status |
|-----------|--------|
| Traceable | Every rule (A1-A5, language cap, no-fabrication) traces to B1-B10 in BASELINE.md |
| Deterministic | Detections are grep-able word/phrase lists and structural diff checks (TODO/stub grep, draft scan) |
| Enforced | Every rule has a BLOCK action; enforcement messages included |
| Tested | Pending Rung-3 rerun of the baseline task; see BASELINE.md honesty note |
| Loophole-tested | 6 loopholes attempted and closed (>= 3 required) |
| Measurable | Baseline frequency table present; promote to real counts on rerun |

**Open Rung-1 item on this skill itself:** the "Tested" criterion is at Rung 1 (Claim) until someone runs the BASELINE.md task against an agent with and without the skill and records the before/after violation counts. That is the exact check that promotes it. Practicing what the skill preaches.
