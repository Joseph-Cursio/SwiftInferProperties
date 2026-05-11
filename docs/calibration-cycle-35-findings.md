# v1.38 Calibration Cycle 35 — Findings (Constraint Engine Batch Migration #1)

Captured: 2026-05-11. swift-infer at v1.38 development tip. The thirty-fifth calibration cycle. **First batch-migration cycle** for the Constraint Engine refactor (PRD §20.2): three templates migrated in a single cycle.

## Headline

**3 templates migrated in one cycle** (Associativity + InvariantPreservation + DualStyleConsistency). Batch-migration approach validated — the V1.36.D mechanical pattern held across all 3 templates without modification, including the first non-FunctionSummary Subject migration (DualStyleConsistencyTemplate uses `Constraint<DualStylePair>`). **Templates migrated: 5 / 10.**

| Metric | Cycle 34 (post-v1.37) | Cycle 35 (post-v1.38) | Δ |
|---|---:|---:|---|
| Surface (default mode) | 109 | 109 | 0 (no inference changes) |
| Acceptance rate | 72.4% | 72.4% (no re-measurement) | 0pp |
| Templates using Constraint Engine | 2/10 | **5/10** | **+3** |
| Test count | 2080 | **2088** | +8 |

## What v1.38 ships

Four workstreams (compressed cadence; closeout bundled):

- **V1.38.A — AssociativityTemplate**. 3 runtime inputs (`vocabulary`, `reducerOps`, `inheritedTypesByName`). Always-3-caveat shape (base 2 + FP advisory OR fallback FP warning).
- **V1.38.B — InvariantPreservationTemplate**. 0 runtime inputs (simplest of all migrated templates). Keypath derived from `summary.invariantKeypath` inside each constraint closure. Gate uses non-nil keypath check.
- **V1.38.C — DualStyleConsistencyTemplate**. First non-FunctionSummary Subject migration: `Constraint<DualStylePair>`. 1 optional runtime input (`carrierKindResolver`). Validates the abstraction's generic Subject parameter against a pair-shaped input.
- **V1.38.D — equivalence tests**. 8 tests across 3 nested suites (one per migrated template). Per-template equivalence across 3-4 fixture corpus + runtime-input propagation + caveat-count invariants.

## Migration pattern stability (3rd validation)

After 5 template migrations across 3 cycles (V1.36 / V1.37 / V1.38), the V1.36.D pattern has held without modification across:

- **3 runtime-input cardinalities**: 0 (InvariantPreservation), 1 (Monotonicity, DualStyleConsistency), 2 (Commutativity), 3 (Associativity).
- **2 Subject shapes**: FunctionSummary (4 templates) + DualStylePair (1 template).
- **3 caveat patterns**: constant (Monotonicity, DualStyleConsistency), conditional-with-keypath (InvariantPreservation), conditional-with-FP (Commutativity, Associativity).

**Conclusion**: the pattern is robust. v1.39 + v1.40 can complete the remaining 5 templates with no design risk.

## Remaining templates (5)

| Template | Subject | Runtime inputs | Complexity vs migrated |
|---|---|---|---|
| RoundTripTemplate | FunctionPair | vocabulary | similar to Commutativity |
| IdempotenceTemplate (non-lifted) | FunctionSummary | vocabulary, inheritedTypesByName | similar to Commutativity |
| IdempotenceTemplate (lifted) | LiftedTransformation | carrierKindResolver, inheritedTypesByName | similar to Composition shape |
| InversePairTemplate (non-lifted) | FunctionPair | vocabulary, EquatableResolver, inheritedTypesByName | higher (3 inputs incl. resolver) |
| InversePairTemplate (lifted) | LiftedInversePair | similar | similar |
| IdentityElementTemplate (non-lifted) | IdentityElementPair | opsWithIdentitySeed, inheritedTypesByName, carrierKindResolver | higher (3 inputs) |
| IdentityElementTemplate (lifted) | LiftedIdentityElementPair | similar | similar |
| CompositionTemplate | LiftedTransformation | vocabulary, carrierKindResolver | higher |

Suggested batching:
- **v1.39**: round-trip + idempotence pair (non-lifted + lifted) — 3 templates.
- **v1.40**: inverse-pair pair + identity-element pair + composition — 5 templates.

Completes the 10-template refactor by v1.40. After completion: the bespoke per-template `suggest(...)` functions all become 4-line wrappers, the abstraction is fully validated, and v1.41+ can address higher-order property composition (PRD §20.2 lookahead).

## Cycle-36 priority

**v1.39 — batch-migrate round-trip + idempotence ×2.** Round-trip is FunctionPair-shaped like DualStyleConsistency; idempotence non-lifted is FunctionSummary-shaped like Commutativity; idempotence lifted introduces `LiftedTransformation` as a new Subject shape. The migration pattern handles all three without modification (validated across V1.36–V1.38).
