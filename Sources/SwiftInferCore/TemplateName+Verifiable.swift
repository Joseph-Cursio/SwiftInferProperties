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
    /// except the three that dispatch elsewhere (`codable-round-trip` has its own
    /// Codable path; `measure-non-negativity` is a measure template; `predicate`
    /// is a totality check and not an algebraic law at all). Derived from
    /// `verifiable` so it stays in step by construction.
    ///
    /// **`predicate` must stay excluded.** `defaultPassSection` falls through to
    /// `algebraicLawPass` for anything in this list, so leaving it in would route
    /// totality into a switch that cannot compose it — and the error message
    /// naming this set would then list a template it cannot actually handle.
    static let strategistAlgebraicLaws: [TemplateName] =
        verifiable.filter {
            $0 != .codableRoundTrip && $0 != .measureNonNegativity && $0 != .predicate
        }
}
