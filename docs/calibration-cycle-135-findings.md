# Calibration cycle 135 — cardinality gate-overrule RATIFIED (full-coverage only)

**Captured 2026-06-15.** No binary change — escalation + decision record
(same posture as cycle 124's Phase B sign-off). The cycle-134 "what's next"
item-1: the owner made the precision call on whether a measured `bothPass`
may overrule the Finding-G `.possible` pin on the gated families
(cardinality, biconditional).

## The decision

**A measured `bothPass` overrules the Finding-G pin per-candidate ONLY at
full action-space coverage (`excludedCaseNames.isEmpty`). A relaxed /
partial bothPass does NOT overrule — it stays `.possible`.**

Applies to both `swiftProjectLintDeferral` families (cardinality +
biconditional) by the same rule. Static score alone still never overrules
(the template-emission path keeps clamping); only *measured execution at
full coverage* can.

## Why this framing (the decisive finding)

Cardinality differs from idempotence/conservation on two axes, and the
second is what set the coverage condition:

1. **Wrong layer (the reason the pin exists).** Mutual exclusion of
   presentation state holds only 33–50% at runtime because it is often
   enforced in the *UI layer* (auto-dismiss), not the reducer. The blanket
   pin distrusts the whole family. Per-candidate execution is exactly the
   evidence the pin is too coarse to give — a reducer that maintains
   `Σ ≤ 1` across its action space *is* reducer-enforced, the high-precision
   subset the pin can't isolate.

2. **The exploration's blind spot aligns with the failure mode.**
   Cardinality's presentation fields are mutated by exactly the action
   types Phase B's relaxed exploration **excludes** —
   `constructibleCases` (`ActionSequenceStubEmitter.swift:232-234`) drops
   composition cases (`binding`, `child`, `PresentationAction`, nested
   `X.Action`). So a *relaxed* bothPass on a cardinality reducer is
   **systematically biased toward false-pass**: it most likely passed
   precisely because it skipped the actions most able to break the mutex —
   sometimes vacuously (the explored subset can't even touch the
   presentation fields).

Full-coverage measured-verify resolves both: with **zero** excluded
actions, the reducer provably maintains the mutex over its *entire* action
space with no UI layer in the loop — a sound per-candidate proof. At
partial coverage the bias bites, so the pin holds. This is why "overrule"
and "overrule at any coverage" have very different soundness, and why the
ratified rule gates on coverage rather than on the bothPass alone.

**Options weighed:** (A) don't overrule — safest, status quo, cardinality's
volume of 8 stays locked; (B) **full-coverage only — RATIFIED**; (C) any
bothPass overrules — max reach but accepts the false-pass bias. Owner chose
B: sound where it applies, honest where it doesn't.

## Binding guardrails (carry into implementation)

- **Coverage is the gate.** The overrule fires only when the verify run
  achieved full action-space coverage (no excluded cases). A partial
  bothPass keeps the existing Phase-B disclosure and stays `.possible`.
- **Disclose the overrule.** A promoted cardinality/biconditional verdict
  MUST state that the Finding-G pin was overruled by full-coverage measured
  execution (e.g. *"reducer-enforced mutex over full action space (0
  excluded); Finding-G pin overruled by measured execution"*) in `detail` +
  render. Explainability is first-class (PRD §4.5).
- **Tier math.** Full coverage + bothPass → ungated `Tier(score: 30 + 50 =
  80)` = `.strong` → `Tier.promoted(byVerifyOutcome: .measuredBothPass)` →
  `.verified`. Same arithmetic as idempotence/conservation; the only change
  is bypassing the `swiftProjectLintDeferral` clamp **for the measured-fold
  path at full coverage**.
- **Single source of truth preserved.** The clamp stays in
  `InteractionInvariantFamily.tier(forScore:)` for the static path; the
  overrule is a *measured-evidence-only* carve-out in
  `InteractionVerifyEvidenceScoring.applied(to:…)`, not a change to the
  gate itself.

## Implementation plan (unblocked, not yet built)

1. **Carry coverage in the evidence.** The full-vs-partial signal currently
   rides only in the verdict `detail` string ("explored M of N … (excluded:
   …)"). Add a structured field to `VerifyEvidence` (e.g. `excludedCount`
   or a `fullCoverage` Bool) so the fold doesn't string-parse.
2. **Carve-out in the fold.** In
   `InteractionVerifyEvidenceScoring.applied(to:evidenceByIdentity:)`: on
   `.measuredBothPass`, if the family carries a `swiftProjectLintDeferral`
   **and** the evidence is full-coverage, compute the **ungated**
   `Tier(score: newScore)` then `.promoted(byVerifyOutcome:)`; otherwise
   keep the clamped path (deferral family at partial coverage → `.possible`).
   Non-deferral families (idempotence/conservation/refint) are unchanged.
3. **Disclosure plumbing.** Append the overrule annotation to the promoted
   verdict's `whySuggested` so it rides into evidence + render.
4. **Measured proof corpus** (`Tests/Fixtures/cardinality-verify-corpus/`
   or extend the existing one): (a) a cardinality reducer with a
   **fully-constructible** Action that enforces the mutex → full-coverage
   bothPass → `.verified` (the overrule proof); (b) a cardinality reducer
   with ≥1 excluded action that bothPasses → **stays `.possible`** (the
   coverage-gate proof); ideally (c) a cardinality false positive →
   `measured-defaultFails` → suppressed. A `.subprocess` measured test
   asserts the three-way split.

## What's next

The decision is ratified and recorded; implementation is unblocked but not
built. Recommended next concrete step is the build above (Phase-B-scale: a
fold carve-out + a verify-ready cardinality corpus). Biconditional rides
the same rule once cardinality lands. Conservation (cycle 134) and
idempotence remain the two families verified end-to-end today; cardinality
becomes the third on a *gated, full-coverage-only* basis.
