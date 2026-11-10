public extension InteractionInvariantFamily {

    /// V2.0 Finding G — the SwiftProjectLint refactor lint a family
    /// cross-references, or `nil` if the family carries no re-home.
    ///
    /// Finding G (cycle 104) established that Cardinality and
    /// Biconditional detect a **representable illegal state** — a
    /// SwiftSyntax-AST smell that SwiftProjectLint already lints
    /// (`mutually-exclusive-presentation-state`, `flag-optional-pair-state`).
    /// The detector is *not* wrong: the State shape it matches is real.
    /// But the inferred *invariant* holds at only 33–50% acceptance as a
    /// runtime property (the corpus showed the predicate can be false at
    /// rest for orthogonal fields, or enforced at a presentation layer the
    /// generated test doesn't model), so the generated test can false-fail
    /// without a real bug.
    ///
    /// Per the cycle-104 decision we **keep emitting the property** (a
    /// failing test may still surface a genuine unguarded illegal state —
    /// the detector can't tell the two apart) but **never promote it past
    /// `.possible`** and cross-reference the lint in the suggestion's
    /// "why this might be wrong" block. This property is the single source
    /// of both the cross-reference rule name *and* the promotion gate:
    /// a non-nil value means "pin at `.possible`, do not promote." Any
    /// future interaction-suggestion score→tier promotion path must
    /// consult it.
    var swiftProjectLintDeferral: String? {
        switch self {
        case .cardinality:
            return "mutually-exclusive-presentation-state"

        case .biconditional:
            return "flag-optional-pair-state"

        case .conservation, .idempotence, .referentialIntegrity, .determinism,
             .unknownActionIsNoOp, .outputDeterminism:
            return nil
        }
    }

    /// The score → tier mapping for this family, honoring the Finding-G
    /// promotion gate (cycle 107 / cycle 112). A family carrying a
    /// `swiftProjectLintDeferral` (cardinality + biconditional) is
    /// **clamped to `.possible` regardless of score** — it detects a
    /// representable-illegal-state refactor smell, not a high-precision
    /// runtime property, so it must never promote off `.possible` even
    /// when a score signal (template scoring *or* a verify-evidence fold)
    /// would otherwise lift it.
    ///
    /// Single source of truth: both template emission
    /// (`InteractionTemplateFamily.tierFor`) and the verify-evidence
    /// re-grade (`InteractionVerifyEvidenceScoring`) route through here,
    /// so the gate can't be bypassed on one path and not the other.
    func tier(forScore score: Int) -> Tier {
        swiftProjectLintDeferral == nil ? Tier(score: score) : .possible
    }
}
