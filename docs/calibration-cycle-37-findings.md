# v1.40 Calibration Cycle 37 — Findings (Constraint Engine Refactor Complete)

Captured: 2026-05-11. swift-infer at v1.40 development tip. The thirty-seventh calibration cycle. **Final batch-migration cycle**, completing the 10-template Constraint Engine refactor per PRD §20.2.

## Headline

**Constraint Engine refactor complete: 10/10 templates migrated.** v1.40 migrates the last 5 suggest entry points: InversePair non-lifted + lifted, IdentityElement non-lifted + lifted, Composition. Behavior preserved bit-for-bit across all 5; all pre-existing tests pass without modification. **Wrapper migration pattern introduced** for templates whose evidence-line rendering doesn't fit the canonical runner output (IdentityElement variants).

| Metric | Cycle 36 (post-v1.39) | Cycle 37 (post-v1.40) | Δ |
|---|---:|---:|---|
| Templates migrated (by name) | 7/10 | **10/10** | +3 |
| Suggest entry points migrated | 8/13 | **13/13** | +5 |
| Subject shapes used | 4 | **7** | +3 (LiftedInversePair, IdentityElementPair, LiftedIdentityElementPair) |
| Test count | 2093 | **2097** | +4 |

## What v1.40 ships

Six workstreams:

- **V1.40.A — InversePairTemplate non-lifted** (Subject: FunctionPair). 4 runtime inputs (vocabulary, **EquatableResolver** — new runtime-input type, inheritedTypesByName, carrierKindResolver). Gate combines forward-param-exists + non-equatable-domain check. 4-base + optional FP advisory caveat.
- **V1.40.B — InversePairTemplate+Lifted** (Subject: LiftedInversePair — first migration). Uses `additionalWhySuggested` for `pair.forward.rationale` insertion. 3-caveat shape with carrier embedded.
- **V1.40.C — IdentityElementTemplate non-lifted** (Subject: IdentityElementPair — first migration). **Wrapper migration pattern**: Constraint drives signals + evidence + identity + carrier; the wrapper rebuilds the Suggestion with bespoke `makeExplainability` to preserve the no-space identity-evidence rendering.
- **V1.40.D — IdentityElementTemplate+Lifted** (Subject: LiftedIdentityElementPair — first migration). Same wrapper pattern.
- **V1.40.E — CompositionTemplate** (Subject: LiftedTransformation; reuses Idempotence+Lifted's Subject type). Uses `additionalWhySuggested` for `lifted.rationale`. 2-constant caveats.
- **V1.40.F — equivalence tests**: 4 nested suites covering 1-3 fixture corpora each + a dedicated test verifying the IdentityElement wrapper pattern preserves the no-space rendering.

## Wrapper migration pattern

The IdentityElement templates' pre-migration `makeExplainability` emits the identity-evidence row with `"\(displayName)\(signature)"` (no space) because the signature is pre-formatted as `": Complex"`. The runner's canonical assembly emits `"\(displayName) \(signature)"` (with space) — would produce `"Complex.zero : Complex"` instead of the pre-migration `"Complex.zero: Complex"`.

Rather than extending the Constraint API with a per-evidence renderer (over-engineering for one template family), V1.40.C/D introduces the **wrapper migration pattern**:

```swift
public static func suggest(...) -> Suggestion? {
    let constraint = makeConstraint(...)
    guard let s = ConstraintRunner.suggest(constraint: constraint, subject: pair) else {
        return nil
    }
    return Suggestion(
        templateName: s.templateName,
        evidence: s.evidence,
        score: s.score,
        generator: s.generator,
        explainability: makeExplainability(for: pair, signals: s.score.signals), // bespoke
        identity: s.identity,
        carrier: s.carrier
    )
}
```

The Constraint still serves as the **data description** of the template's scoring + evidence + identity logic; only the rendering hook is bespoke. Future templates with similar rendering quirks can adopt this pattern without modifying the Constraint API.

## Migration pattern stability (5th and final validation)

Across 5 cycles (V1.36 + V1.37 + V1.38 + V1.39 + V1.40) and 13 suggest entry points migrated, the pattern held with:
- **5 runtime-input cardinalities**: 0 / 1 / 2 / 3 / 4.
- **7 Subject shapes**: FunctionSummary, FunctionPair, DualStylePair, LiftedTransformation, LiftedInversePair, IdentityElementPair, LiftedIdentityElementPair.
- **5 caveat patterns**: constant, keypath-conditional, FP-conditional (Commutativity/Associativity), carrier-embedded (Idempotence+Lifted, InversePair+Lifted), FP-extending (InversePair non-lifted).
- **2 Constraint API extensions over 5 cycles**: `additionalWhySuggested` (V1.39 — discovered when migrating Idempotence+Lifted). No other extensions needed.
- **Wrapper migration pattern** as an escape hatch for templates with rendering quirks (V1.40.C/D).

The abstraction is robust enough to express every shipped template via Constraint. v1.41+ work can build on it.

## What's next

The Constraint Engine refactor closes. v1.41+ opens onto:

1. **Higher-order property composition** (PRD §20.2 lookahead). The constraint-as-data shape enables expressing "a Group constraint composes a Semigroup constraint + an identity-element constraint + an inverse-pair constraint." Multi-cycle architectural extension.
2. **Project-vocabulary constraint registration** (also PRD §20.2). User-defined constraints loaded from `.swiftinfer/constraints.swift` or a YAML config. Builds on the Constraint API.
3. **Backlog items from prior cycles**:
   - Dominant-pattern cluster-classification refinement (v1.35 finding).
   - Cross-type abstraction discovery (v1.35 deferred).
   - Incremental indexing (v1.33 deferred).
   - Natural-language query DSL (v1.33 deferred).
   - SQLite backend (v1.33 deferred).
4. **Test-execution evidence** (architectural shift; user raised it back at v1.25). Still the highest-leverage long-term move; awaits explicit design discussion before any implementation.

## Conclusion

v1.40 closes the 5-cycle Constraint Engine refactor. Every template's `suggest(...)` is now a 4-line `ConstraintRunner.suggest` wrapper (with the IdentityElement variants using the wrapper migration pattern to preserve a one-character rendering quirk). The v1.36 PRD §20.2 claim that "the constraint-engine upgrade can replace the matcher behind the scoring engine without touching the scoring engine itself or any downstream contract" is now empirically validated across 13 entry points and 7 Subject shapes.

Calibration data unchanged (acceptance rate 72.4% holds; no template-precision drift across the refactor). The matcher layer is now constraint-driven; templates land as data; higher-order composition (PRD §20.2 lookahead) is unblocked.
