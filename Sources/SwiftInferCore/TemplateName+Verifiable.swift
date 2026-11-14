public extension TemplateName {
    /// The templates `swift-infer verify` can measure directly — the canonical
    /// "supported templates" list, in dispatch/display order.
    static let verifiable: [TemplateName] = [
        .roundTrip, .codableRoundTrip, .idempotence, .commutativity, .associativity,
        .idempotenceLifted, .dualStyleConsistency, .monotonicity,
        .involution, .binaryIdempotence, .homomorphism, .multiplicativeHomomorphism,
        .measureNonNegativity, .predicate, .differentialEquivalence,
        // **Verifiable for two of its ten roles, and that is the honest state.**
        // `lowercased` / `uppercased` return `String` in every spelling, so their check
        // needs no conformance the tool must prove. The other eight stay advisory:
        // `sorted` needs `Element: Comparable`, `deduplicated` needs `Hashable`, `clamped`
        // needs the caller's bounds, `reversed` / `shuffled` need the input beside the
        // result, and the escaping pair has no universal scheme. Emitting a check the
        // emitter cannot justify is what `criterion-a-unmet-subject.md` measured at 89%
        // of output failing to compile, so `composeRolePostconditionPass` returns nil
        // rather than guessing.
        .rolePostcondition,
        // `f(from: v, to: v).isEmpty` — complete without author input, and its oracle needs no
        // conformance (#701). Composed by `composeEmptyRangePass`.
        .emptyRange,
        // `value.p == (value.m > 0)` — complete without author input once the index records the
        // measure's name and its property-or-method shape (#701). Composed by
        // `composeEmptinessAgreementPass`.
        .emptinessAgreement,
        // `(L...U as ClosedRange<Double>).contains(Double(f(x)))` — the author stated the bounds,
        // and the index records them (#701). Composed by `composeDocumentedRangePass`, which
        // routes beside `predicate` through `totalityLawPass`: it shares totality's one generator
        // per parameter, not an algebraic shape.
        .documentedRange,
    ]

    // swiftprojectlint:disable:next parallel-list-drift
    /// The four templates the v1.46 hardcoded per-carrier emitters support.
    ///
    /// (Coincidentally shares three algebraic names with the unrelated
    /// `TemplateSignal` axiom-signal enum — see the note there; not drift.)
    static let v146Hardcoded: [TemplateName] = [
        .roundTrip, .idempotence, .commutativity, .associativity
    ]

    /// Templates whose default-fail regression test can be auto-derived: the
    /// v1.46 hardcoded set plus `monotonicity`. Written as that relationship so
    /// the two lists cannot drift apart — which is exactly what they had begun to.
    static let regressionAutoDerivable: [TemplateName] = v146Hardcoded + [.monotonicity]

    /// The algebraic-law templates the strategist routes: everything verifiable
    /// except the four that dispatch elsewhere (`codable-round-trip` has its own
    /// Codable path; `measure-non-negativity` is a measure template; `predicate`
    /// is a totality check and not an algebraic law at all; `documented-range`
    /// rides totality's per-parameter operands). Derived from `verifiable` so it
    /// stays in step by construction.
    ///
    /// **`predicate` and `documented-range` must stay excluded.** `defaultPassSection`
    /// falls through to `algebraicLawPass` for anything in this list, so leaving
    /// either in would name, in the error message listing this set, a template the
    /// algebraic switch cannot compose.
    static let strategistAlgebraicLaws: [TemplateName] =
        verifiable.filter {
            ![.codableRoundTrip, .measureNonNegativity, .predicate, .documentedRange].contains($0)
        }
}
