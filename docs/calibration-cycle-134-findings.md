# Calibration cycle 134 — conservation is the second family verified by measured execution

**Captured 2026-06-15.** No binary change (fixtures + two tests). The
"option #3" follow-up to cycle 133: extend the measured-verify path beyond
idempotence to a **second interaction family**. Owner steer (this session):
*"conservation first, then escalate"* — prove the path un-gated on the
cleanest non-idempotence shape now; bring the cardinality/biconditional
gate-overrule (the precision call) as a separate ratify step later.

## Headline finding — the mechanism was already family-generic

Scoping recon (two parallel investigations) set out to size *building* a
second measured-verify path. It found the path **already exists for all
five families** — idempotence was merely the only one ever demonstrated
end-to-end:

- **The per-step check is generic.** `ActionSequenceStubEmitter.makePerStepCheck`
  (`Sources/SwiftInferCLI/ActionSequenceStubEmitter+FamilyChecks.swift:16-46`)
  emits `precondition(<predicate>, "… invariant violated")` for
  conservation / cardinality / referentialIntegrity / biconditional,
  evaluated after each action inside the exploration loop
  (`assembleStub` → `makeIterationBody`, `…StubEmitter.swift:72,176-184`).
  Idempotence is the *odd one out* — its predicate is an action case
  verified by the post-loop double-apply check (`makeIdempotenceCheck`),
  not a State-boolean.
- **The emitter accepts all five.** `validateInvariant`
  (`…StubEmitter.swift:199-208`) returns for every family; no rejection.
- **The fold is generic.** `InteractionVerifyEvidenceScoring.applied(to:…)`
  (`Sources/SwiftInferCore/InteractionVerifyEvidenceScoring.swift:38-68`)
  adds `verifyBothPassWeight` (+50) and recomputes the tier through
  `family.tier(forScore:)` — the single-source-of-truth Finding-G gate
  (`InteractionInvariantSuggestion.swift:234-236`). Conservation carries
  **no** `swiftProjectLintDeferral` (`…Suggestion.swift:216`), so the gate
  does not clamp it.
- **The promotion math reaches `.verified`.** Conservation ships at
  `initialScore = 30` (`.possible`). A measured bothPass: 30 + 50 = **80**,
  which is `.strong` (`Tier(score:)` band `75...`,
  `Sources/SwiftInferCore/Tier.swift:50-53`), and
  `Tier.promoted(byVerifyOutcome: .measuredBothPass)` lifts `.strong →
  .verified` (`Tier.swift:70-73`).

So the blocker was never the mechanism — it was the same one as cycle 126:
**no curated verify-ready corpus had ever exercised a non-idempotence
family end-to-end.** This cycle supplies it for conservation. Like the
`.tca` Phase A spike (cycle 122), running the never-run path is itself the
value: it confirms the generic stub actually compiles and executes for a
State-boolean predicate.

## Why conservation first (the family ranking)

The four non-idempotence families split two ways:

| Family | Corpus vol. | Finding-G gate | Mechanism friction |
|---|---|---|---|
| **Conservation** | 1 | none (can promote) | none — cleanest |
| Referential integrity | 2 | none (can promote) | predicate needs element `Identifiable` (compile friction) |
| Cardinality | 8 | **pinned `.possible`** | none |
| Biconditional | 2 | **pinned `.possible`** | none |

- **Conservation / refint** are un-gated and can promote today, but have
  near-zero corpus volume (the cycle-119 trap: tractable, moves no
  baseline metric). Demonstrating them is *completeness*, not recall.
- **Cardinality / biconditional** carry the volume (cardinality = 8,
  second only to idempotence's 55) but are **deliberately pinned** by
  Finding-G because the static smell holds only 33–50% at runtime / drifts
  by design. A measured bothPass on them currently does nothing (the fold
  routes through the same gate).

The strategic insight (deferred to a later cycle): **measured execution is
exactly the evidence that could overrule the Finding-G pin per-candidate**
— a real reducer that demonstrably maintains the invariant under
deterministic exploration is per-candidate proof the static analyzer
can't give. But lifting that pin is a **precision decision identical in
character to the Phase B sign-off (cycles 123→124)**, not engineering. So
cycle 134 does the zero-risk half (conservation, un-gated) and leaves the
gate-overrule for owner ratification.

Conservation beats refint for *first* because its predicate
(`state.count == state.items.count`) compiles for any array element, while
refint's `collection.contains { $0.id == selected }` requires the element
to be `Identifiable` — a downstream compile gate.

## What shipped — the verify-ready conservation corpus

`Tests/Fixtures/conservation-survey-corpus/` — two self-contained public
reducers (`(State, Action) -> State`, zero-arg `Equatable` State,
payload-free `CaseIterable` Action):

- **`InventoryReducer`** — `count: Int` paired with `items: [Int]`; every
  transition (`addItem` / `removeLast` / `clearAll`) keeps the two in
  lockstep. The ConservationWitness `state.count == state.items.count`
  holds at `State()` (0 == 0) and after every action → **`measured-bothPass`**.
- **`BadgeReducer`** — the deliberate **false positive** (the conservation
  analogue of idempotence's `setBadge`). `badgeCount: Int` paired with
  `notifications: [Int]`, so the witness forms statically — but `.receive`
  bumps `badgeCount` *without* appending, so the count drifts ahead of the
  array. The per-step precondition traps → **`measured-defaultFails`** →
  suppressed. Only execution disproves the name-shaped suggestion.

## Measured baseline

`verify-interaction --all --family conservation` over the packaged corpus:
**2 identities → 1 `measured-bothPass` (InventoryReducer) + 1
`measured-defaultFails` (BadgeReducer)**. The fold promotes Inventory
`.possible → .verified`; `discover-interaction` renders it `(Verified)`
and drops the suppressed Badge. The campaign thesis now holds on a
*second* family: promotion gated on execution, execution catching a
name-based false positive the static detector cannot.

## Verification

- **Fast:** `ConservationSurveyCorpusTests` (SwiftInferCLITests, ~0.3s) —
  packaging + discovery surfaces exactly the two conservation identities,
  both at `.possible` (no-evidence baseline).
- **Measured (`.subprocess`):** `ConservationSurveyCorpusMeasuredTests`
  (SwiftInferIntegrationTests, ~34s) — 2 identities → 1 bothPass + 1
  defaultFails; evidence 2/1/1; discover promotes Inventory to `(Verified)`,
  suppresses Badge, no `(Possible)` survivor.
- `swiftlint` clean on the four new files. Fast suite otherwise green
  (3206 tests; the lone failing issue is the pre-existing `DequeModule`
  perf-budget timing flake — 3.21s vs 3.0s under concurrent build load,
  unrelated to this change, count varies run-to-run).

## What's next

Conservation is verified end-to-end; the measured-verify path is proven
family-generic, not idempotence-specific. Remaining, in value order:

1. **Escalate the gate-overrule decision (cardinality / biconditional).**
   The high-volume families are pinned by Finding-G. Bring the owner a
   Phase-B-style precision call: *should a measured bothPass overrule the
   `.possible` pin per-candidate (while static score alone still can't)?*
   If yes, the only code change is in `tier(forScore:)` /
   `InteractionVerifyEvidenceScoring` — the stub already emits the
   cardinality/biconditional preconditions. Disclose exploration coverage
   the way Phase B discloses excluded action types.
2. **Referential integrity** — the second un-gated family; cheap once an
   `Identifiable`-conformance gate (or skip) guards the
   `contains { $0.id == … }` predicate at stub-emit time. Completeness, low
   recall (2 corpus candidates).
3. Corpus volume for conservation — same cost model as the `.tca` corpus
   (one stub-only incremental per reducer via the cycle-129 warm workdir).
   Volume, not coverage.
