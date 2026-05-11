# v1.37 Calibration Cycle 34 — Findings (Constraint Engine Migration #2)

Captured: 2026-05-11. swift-infer at v1.37 development tip. The thirty-fourth calibration cycle. Second template migration to the Constraint Engine (PRD §20.2).

## Headline

**MonotonicityTemplate migrated via the V1.36.D mechanical pattern.** Behavior preserved bit-for-bit (all 32 pre-existing MonotonicityTemplate tests pass without modification + 3 new equivalence tests on a 7-fixture corpus). **Templates migrated: 2 / 10.** The migration pattern is now validated against two representative unary-summary templates with different runtime-input shapes (Commutativity: 2 runtime inputs incl. inheritance index; Monotonicity: 1 runtime input, constant caveats).

| Metric | Cycle 33 (post-v1.36) | Cycle 34 (post-v1.37) | Δ |
|---|---:|---:|---|
| Surface (default mode) | 109 | 109 | 0 |
| Acceptance rate | 72.4% | 72.4% (no re-measurement) | 0pp |
| Templates using Constraint Engine | 1/10 | **2/10** | +1 |
| Test count | 2077 | **2080** | +3 |

## What v1.37 ships

Two workstreams (compressed A–H cadence):

- **V1.37.A**: MonotonicityTemplate migration. `suggest(for:vocabulary:)` is now a 4-line `ConstraintRunner.suggest` wrapper. New `makeConstraint(vocabulary:)` factory + `accumulatedSignals(for:vocabulary:)` helper + `makeCaveats()` helper. Constant caveat list (no FP-conditional path like Commutativity).
- **V1.37.B**: 3 equivalence tests on a 7-fixture corpus (curated verb `count`, curated suffix `userCount`, bare-shape, non-Comparable codomain reject, multi-param reject, mutating reject, non-deterministic veto). Vocabulary propagation + constant-caveats verification.

## Migration pattern stability

The pattern documented in V1.36.D held without modification:

1. ✓ Extract `makeConstraint(<runtime-inputs>) -> Constraint<Subject>` factory.
2. ✓ Extract `accumulatedSignals(for:...)` helper.
3. ✓ Extract `makeCaveats(...)` helper.
4. ✓ Rewrite `suggest(...)` as a 4-line `ConstraintRunner.suggest` wrapper.
5. ✓ Existing tests pass without modification + add equivalence tests.

**Observation**: the migration touch is purely additive at the file level — no existing private helper is renamed or removed. The pre-migration `orderedCodomainSignal`, `nameSignal`, `accumulatorBodySignal`, `nonDeterministicVeto`, `makeEvidence`, `makeIdentity`, `displayName`, `signature` private statics continue to exist; the new `accumulatedSignals(for:vocabulary:)` orchestrates them, and `makeExplainability(for:signals:)` becomes dead code (the runner's default explainability assembly replaces it). v1.38+ could prune dead code per template; v1.37 leaves it in place to keep migration commits surgical.

## v1.38+ batch-migration assessment

After 2 migrations against 2 representative shapes, the abstraction has held without surprises. **Recommendation**: batch the remaining 8 migrations in v1.38 if the conversation context allows, or split into v1.38 (4 templates) + v1.39 (4 templates) if more conservative pacing is preferred. The templates remaining:

| Template | Subject | Runtime inputs | Complexity vs Monotonicity |
|---|---|---|---|
| RoundTripTemplate | FunctionPair | vocabulary | similar (pair-shape gate; same closure structure) |
| InversePairTemplate | FunctionPair | EquatableResolver, inheritedTypes, etc. | higher (5+ runtime inputs threaded through helpers) |
| InversePairTemplate+Lifted | LiftedInversePair | similar to InversePair | similar |
| IdempotenceTemplate | FunctionSummary | vocabulary, inheritedTypes, etc. | similar to Commutativity |
| IdempotenceTemplate+Lifted | LiftedTransformation | carrierKindResolver, inheritedTypes | similar |
| AssociativityTemplate | FunctionSummary | vocabulary, inheritedTypes | nearly identical to Commutativity |
| IdentityElementTemplate | IdentityElementPair | opsWithIdentitySeed, inheritedTypes, carrierKindResolver | higher |
| IdentityElementTemplate+Lifted | LiftedIdentityElementPair | similar | similar |
| DualStyleConsistencyTemplate | DualStylePair | vocabulary | similar to Monotonicity |
| CompositionTemplate | LiftedTransformation | vocabulary, carrierKindResolver | higher |
| InvariantPreservationTemplate | FunctionSummary | (none — single-arg suggest) | simplest of all |

A natural batching: v1.38 = AssociativityTemplate + InvariantPreservationTemplate + DualStyleConsistencyTemplate (lowest-complexity 3). v1.39 = RoundTrip + Idempotence pair (non-lifted + lifted). v1.40 = InversePair + IdentityElement (with their lifted variants) + Composition. Each in 1 cycle.

## Cycle-35 priority

**v1.38 batch-migrate the next 3 simplest templates** (Associativity, InvariantPreservation, DualStyleConsistency) — all single-suggest shape with minimal runtime inputs. The user can redirect to per-template per-cycle pacing if they prefer the slower cadence.

Alternative paths from prior-cycle backlogs:
- Dominant-pattern cluster-classification refinement (v1.35 finding)
- Cross-type abstraction discovery (v1.35)
- Incremental indexing (v1.33)
- SQLite backend (v1.33)

## Conclusion

v1.37 closes the second Constraint Engine migration. The mechanical pattern documented at V1.36.D held without modification — strongly suggests v1.38+ batch migration is safe. 2/10 templates migrated; 8 remaining; aggregate refactor likely completes in 2-3 more cycles.
