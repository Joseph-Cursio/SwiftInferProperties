# Calibration cycle 136 — cardinality gate-overrule SHIPPED (full-coverage only)

**Captured 2026-06-15. v1.129.0** (binary change). Implements the cycle-135
ratified decision: a measured `bothPass` overrules the Finding-G `.possible`
pin on the gated families (cardinality / biconditional) **only at full
action-space coverage**. Cardinality becomes the third interaction family
that measured execution can promote to `.verified` — on a gated,
full-coverage-only basis.

## What shipped

A **measured-evidence-only carve-out** in the discover-side fold. Static
score still never overrules; the gate (`InteractionInvariantFamily.
tier(forScore:)`) is unchanged — the overrule lives entirely in
`InteractionVerifyEvidenceScoring`, reachable only when persisted verify
evidence exists.

1. **Coverage signal on the evidence** (`SwiftInferCore/VerifyEvidence.swift`
   + `SwiftInferCLI/InteractionVerifyOutcomeParser.swift`). New optional
   `excludedActionCount: Int?` — `0` = full coverage, `> 0` = partial, `nil`
   = unrecorded (legacy, treated conservatively as *not* full). Optional so
   old `verify-evidence.json` decodes unchanged (synthesized Codable uses
   `decodeIfPresent`/`encodeIfPresent` — no schema bump).

2. **Stamp it for every carrier** (`VerifyInteractionPipeline+Evidence.swift`).
   `foldPartialExplorationDisclosure` now stamps `excludedActionCount =
   ActionSequenceStubEmitter.excludedCaseNames(candidate).count` on every
   result (it was `.tca`-disclosure-only before). That count is `0` for
   non-`.tca` CaseIterable reducers and all-constructible `.tca` reducers,
   and `> 0` only for genuinely relaxed `.tca` exploration. `makeEvidence`
   carries it into `VerifyEvidence`.

3. **The fold carve-out** (`InteractionVerifyEvidenceScoring.swift`, extracted
   to `gradedForBothPass` for the SwiftLint closure-length cap). On
   `.measuredBothPass`:
   ```
   overruled = family.swiftProjectLintDeferral != nil   // gated family
            && evidence.excludedActionCount == 0         // full coverage
   effectiveTier = overruled ? Tier(score: newScore)     // ungated → .strong
                             : family.tier(forScore: newScore)  // clamped
   ```
   then `.promoted(byVerifyOutcome: .measuredBothPass)`. A gated family at
   full coverage: 30 + 50 = 80 → `.strong` → `.verified`, with a disclosure
   appended to `whySuggested` (*"Finding-G pin overruled by full-coverage
   measured execution — 0 excluded actions"*). A gated family at partial /
   `nil` coverage keeps the clamp → `.possible`. Non-gated families
   (idempotence / conservation / refint) are untouched (`gatedTier ==
   ungatedTier`, no disclosure).

## Why coverage is the gate (recap of the cycle-135 reasoning)

Cardinality's failure mode lives in exactly the action types Phase B's
relaxed exploration *excludes* (`binding` / `PresentationAction` / nested
`X.Action`). A *partial* bothPass is therefore biased toward false-pass —
it most likely passed because it skipped the actions most able to break the
mutex. At **full** coverage (0 excluded), the reducer provably maintains
`Σ ≤ 1` over its entire action space with no UI layer in the loop — a sound
per-candidate proof, exactly the high-precision subset the blanket pin was
too coarse to isolate.

## Proof corpus

`Tests/Fixtures/cardinality-verify-corpus/` — three real `@Reducer`s, each
with two presentation Bool flags (one CardinalityWitness apiece):

- **RouterFeature** — enforces the mutex; all Action cases payload-free →
  **full-coverage `bothPass`** → pin OVERRULED → `.verified`.
- **DrawerFeature** — enforces the mutex too (also `bothPass`), but its
  Action carries a non-constructible `received(Data)` case → **partial
  coverage** (`excludedActionCount == 1`) → pin NOT overruled → stays
  `.possible`. The coverage gate, not the bothPass, decides.
- **LeakyFeature** — does NOT enforce the mutex (the cardinality false
  positive) → `measured-defaultFails` → suppressed.

## Verification

- **Fast (Core):** `InteractionVerifyEvidenceScoringTests` — extended to 11
  tests covering full-coverage overrule → `.verified`, partial → `.possible`,
  legacy `nil` → `.possible`, biconditional overrule, and the ungated-family
  invariance.
- **Fast (CLI):** `CardinalityVerifyCorpusTests` (~0.2s) — discovery surfaces
  exactly the three cardinality identities at `.possible`, no other family.
- **Measured (`.subprocess`):** `CardinalityVerifyCorpusMeasuredTests` (~72s)
  — the three-way split end-to-end: survey → 2 bothPass + 1 defaultFails;
  evidence carries `excludedActionCount` 0 (Router) and 1 (Drawer); discover
  promotes Router to `(Verified)` with the overrule disclosure, keeps Drawer
  at `(Possible)`, suppresses Leaky.
- `swiftlint` clean. Full `swift test` green **except** the four PRD §13
  wall-clock perf budgets, which flake under concurrent `.subprocess` build
  load (all pass in isolation: DequeModule 2.2s, Synthetic 0.8s/2.2s,
  TestLifter 1.9s/3.1s) — unrelated to this change.

## What's next

Biconditional now rides the same rule for free (the fold is family-generic
over `swiftProjectLintDeferral`); it needs only a verify-ready corpus to
demonstrate, the same way this cycle did for cardinality. Lower-value:
referential integrity (second un-gated family) once an `Identifiable` gate
guards its `contains { $0.id == … }` predicate. The frozen 50.5%
measured-execution rate is a *discovery-corpus* metric; this cycle widens
*which families* measured verify can promote, not that number.
