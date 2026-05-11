# v1.36 Calibration Cycle 33 — Findings (Constraint Engine Foundation)

Captured: 2026-05-11. swift-infer at v1.36 development tip. The thirty-third calibration cycle and the **first cycle of the multi-cycle Constraint Engine refactor** (PRD §20.2).

## Headline

**Constraint Engine foundation shipped + first template migrated.** v1.36 introduces the `Constraint<Subject>` abstraction + `ConstraintRunner` orchestrator (V1.36.A/B) and migrates `CommutativityTemplate` to express itself as a Constraint (V1.36.C). Behavior is preserved bit-for-bit (all 54 pre-existing CommutativityTemplate tests pass without modification + 4 new equivalence tests on a 7-fixture corpus). **No acceptance-rate re-measurement** — v1.36 is an architectural refactor of the matcher; per-template inference precision unchanged by construction.

| Metric | Cycle 32 (post-v1.35) | Cycle 33 (post-v1.36) | Δ |
|---|---:|---:|---|
| Surface (default mode) | 109 | 109 | 0 (no inference changes) |
| Acceptance rate | 72.4% (cycle-27 carries) | 72.4% (no re-measurement) | 0pp |
| Mechanism classes | 16 | 16 (no new) | 0 |
| Templates using Constraint Engine | 0/10 | **1/10** | +1 |
| Test count | 2059 | **2077** | +18 |

## What v1.36 ships

Three workstreams:

- **V1.36.A**: `Constraint<Subject>` data model in `SwiftInferCore`. Generic over Subject (FunctionSummary / FunctionPair / LiftedTransformation / IdentityElementPair / DualStylePair). 6 closure-typed fields: `appliesTo`, `signals`, `evidence`, `identity`, `carrier` (defaults nil), `caveats` (defaults []). All `@Sendable` for future-safe parallel evaluation. 7 unit tests.

- **V1.36.B**: `ConstraintRunner.suggest(constraint:subject:)` orchestrator. Pure function: `(constraint, subject) → Suggestion?`. Returns nil on gate-false OR `Score(signals:)` landing in `.suppressed` tier. Default `makeExplainability(...)` assembles the §4.5 block from evidence + signals + caveats — exposed module-internal for testing without going through `suggest(...)`. 7 unit tests including gate-short-circuit verification (signals closure not invoked when gate is false).

- **V1.36.C**: `CommutativityTemplate` migration. `suggest(for:)` becomes a 4-line wrapper around `ConstraintRunner.suggest`. New `makeConstraint(vocabulary:inheritedTypesByName:)` factory captures runtime inputs into `@Sendable` closures. Behavior preserved bit-for-bit:
  - All 54 pre-existing CommutativityTemplate tests pass without modification.
  - 4 new equivalence tests verify identical Suggestion output across a 7-fixture corpus (curated-name accept, anti-commutativity reject, type-shape rejects, non-deterministic veto, bare-shape accept, FP storage, vocabulary propagation, inheritance-index propagation).

## Migration template

The CommutativityTemplate migration establishes a reusable pattern for the v1.37+ migrations of the remaining 9 templates:

1. Identify the constraint factory function shape: `makeConstraint(<runtime-inputs>) -> Constraint<Subject>`.
2. Extract the signal-accumulation logic into a helper (e.g., `accumulatedSignals(for:...)`).
3. Extract the caveat-list logic into a helper (e.g., `makeCaveats(for:)`).
4. Rewrite `suggest(...)` as a wrapper that calls `ConstraintRunner.suggest(constraint:subject:)`.
5. Verify with the template's existing test suite + add new equivalence tests against a fixture corpus.

The pattern is **mechanical** — no template-specific design decisions remain for the remaining 9 migrations. Future cycles can pick them up in any order; per-template equivalence tests are the safety net.

## Scope boundaries observed

- **In scope**: Constraint abstraction, runner, first template migrated, equivalence tests.
- **Out of scope (v1.37+)**: migrate the remaining 9 templates (round-trip, idempotence non-lifted + lifted, monotonicity, associativity, inverse-pair non-lifted + lifted, identity-element non-lifted + lifted, dual-style-consistency, composition, invariant-preservation).
- **Out of scope (v1.38+)**: cross-constraint composition ("a Group constraint composes Semigroup + identity-element + inverse-pair").
- **Out of scope (v1.39+)**: project-vocabulary constraint registration (user-defined constraints loaded from `.swiftinfer/constraints.swift`).

## Risk + mitigation status

- **Risk addressed**: equivalence tests fail to catch a subtle output difference. **Mitigation outcome**: 54 pre-existing tests pass without modification; 4 new equivalence tests pass; structural `==` on the whole `Suggestion` catches signal-ordering, identity-hash, carrier, explainability drift.
- **Risk addressed**: `@Sendable` closure capture issues. **Mitigation outcome**: `Vocabulary` is `Sendable` per its declaration; `[String: Set<String>]` is `Sendable` as a value type; closures compile cleanly.
- **Risk addressed**: scope creep. **Mitigation outcome**: hard cap at one template migrated; cycle 33 closes with the foundation laid and a reusable pattern documented.

## Cycle-34 priority

Per the multi-cycle Constraint Engine refactor plan:

1. **v1.37 — second template migration**. The MonotonicityTemplate is the natural next candidate: unary-summary shape like Commutativity, well-tested, no exotic dependencies. After v1.37 the abstraction has been validated against 2 templates; v1.38+ can batch-migrate the remaining 8 if confidence is high.

2. **v1.38+ alternative paths** from the v1.35 + v1.33 backlogs:
   - Dominant-pattern cluster-classification refinement (v1.35 finding)
   - Cross-type abstraction discovery (v1.35 deferred)
   - Incremental indexing (v1.33 deferred)
   - SQLite backend (v1.33 deferred)

## Conclusion

v1.36 lays the Constraint Engine foundation (PRD §20.2) with a focused 3-workstream cycle. The CommutativityTemplate migration validates the abstraction's API against a real template; the bit-for-bit equivalence guarantee preserves calibration data across the refactor. The migration pattern is now mechanical and reusable for v1.37+ template migrations.

v1.37 second-template migration (likely MonotonicityTemplate) begins next.
