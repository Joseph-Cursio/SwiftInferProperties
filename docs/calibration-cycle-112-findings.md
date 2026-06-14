# Calibration cycle 112 — interaction verify-evidence consumer (the join closes)

> **STATUS: SHIPPED (v1.119.0).** Second half of the "M9" join. The
> `discover-interaction` render path now **reads** the
> `.swiftinfer/verify-evidence.json` the cycle-111 producer writes and
> folds each measured outcome into the suggestion grade. A measured
> `.measuredBothPass` lifts an idempotence pick off `.likely`; a
> `.measuredDefaultFails` suppresses it. The producer→consumer chain is
> now end-to-end. Captured 2026-06-14.

## Context

Cycle 110 made interaction measured execution run from the CLI; cycle 111
made `verify-interaction` **persist** each outcome to
`verify-evidence.json` keyed by the invariant identity. But nothing read
that evidence — discover-interaction always showed the base, pre-verify
tier. This cycle ships the read side, so measured execution can finally
change what `discover-interaction` surfaces.

## What shipped

**1. `InteractionVerifyEvidenceScoring` (SwiftInferCore)** — the
`InteractionInvariantSuggestion` analogue of the algebraic
`VerifyEvidenceScoring`. `applied(to:evidenceByIdentity:)` folds each
outcome:

- `.measuredBothPass` → `score + VerifyEvidenceScoring.verifyBothPassWeight`
  (**+50, the shared constant** so the two folds stay calibrated together),
  tier recomputed **through the Finding-G gate**, then
  `Tier.promoted(byVerifyOutcome:)`. Idempotence `.likely` (40) →
  `.verified` (40 + 50 = 90 → `.strong` → `.verified`).
- `.measuredDefaultFails` → `.suppressed` (an executed counterexample, not
  a heuristic guess — the same precision argument as the algebraic veto,
  cycle 63).
- `.measuredEdgeCaseAdvisory` / `.measuredError` /
  `.architecturalCoveragePending` → score-neutral pass-through. No
  evidence → identical value (`==` holds).

**2. Finding-G gate lifted to a single source of truth.** The
score→tier clamp (cardinality + biconditional pinned at `.possible`
regardless of score) moved from `InteractionTemplateFamily.tierFor`
(SwiftInferTemplates, template-emission only) to a new public
`InteractionInvariantFamily.tier(forScore:)` in SwiftInferCore.
`tierFor` now delegates to it, and the verify-evidence fold calls the
same method — so a measured `.measuredBothPass` on a cardinality pick
raises its score but **cannot** promote it off `.possible`. The gate
can't be honored on one path and bypassed on the other.

**3. Consumer wired into the `discover-interaction` render path.** New
`gradedByVerifyEvidence(_:workingDirectory:diagnostics:)` loads the
store (best-effort; warnings → diagnostics, absent file → no-op) and
applies the fold. Called from `run` and `runPipeline` **after**
`collectSuggestions`, **before** the visibility cut — so a `bothPass`
lift can clear the cut and a `defaultFails` veto drops below it.
Mirrors the algebraic `loadVerifyEvidenceMap` in `SwiftInferCommand`.

**Why the fold is on the render path, not in `collectSuggestions`.**
That leg is shared with `drift-interaction`'s baseline diff, which must
keep the pre-verify, score-derived tier — a baseline snapshot is a
surface marker, not a verified decision (same posture as the algebraic
`Baseline.tier`). Folding evidence into the shared collector would leak
verified tiers into the baseline. drift-interaction can adopt evidence
on its own terms in a later cycle.

## A small helper added

`InteractionInvariantSuggestion.with(score:tier:whySuggested:whyMightBeWrong:)`
— a copy-with for the fold to re-grade a suggestion without restating
every field.

## Verification

- **Core unit (`InteractionVerifyEvidenceScoringTests`, 8 tests):**
  exhaustive over the five outcomes × the gate — bothPass→verified for
  idempotence; bothPass **does not** promote cardinality/biconditional
  (gate pins `.possible` though score rises to 80); defaultFails→suppressed;
  the three neutral outcomes and no-evidence pass through `==`; order
  preserved and only matching picks re-graded.
- **CLI end-to-end (`DiscoverInteractionVerifyEvidenceTests`, 3 tests):**
  a real `.swiftinfer/verify-evidence.json` (written exactly as
  `verify-interaction` writes it) is loaded, folded, and reflected in the
  rendered stream — idempotence renders `Score: 90 (Verified)` on
  bothPass, drops out entirely on defaultFails, stays `40 (Likely)` with
  no evidence file. Proves the load → fold → render wiring.
- **Suites:** full fast suite green (3178 tests; only the known §13
  perf-budget timing flakes under load, which pass in isolation).
  SwiftLint clean. The `tierFor` refactor is behavior-preserving — the
  template + tier suites pass unchanged.

## What's next — corpus packaging, then a measured campaign

The producer writes and the consumer reads; the join is closed. The
remaining A1 item is **CLI corpus packaging** (carried from cycle 110):
the HandRolled + TCA corpora aren't standalone module-named SwiftPM
packages, so `verify-interaction` can't yet run a measured survey over
the 39 idempotence identities at scale. Once they are:

1. Run `verify-interaction` over the idempotence corpus, harvesting
   `.measuredBothPass` / `.measuredDefaultFails` into `verify-evidence.json`.
2. `discover-interaction` then surfaces the survivors at `.verified` and
   drops the disproven — `.strong`/`.verified` **gated on execution**,
   not re-triage.

**Default (no-evidence) idempotence stays `.likely`** — promotion past it
now requires a measured `.measuredBothPass` on disk, which is exactly the
gate the A1 campaign wanted.
