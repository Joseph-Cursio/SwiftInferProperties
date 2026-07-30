// Widens the algebraic corpus to the IDEMPOTENCE family — static unary
// `(Confidence) -> Confidence` ops where `f(f(x)) == f(x)`. Same `.caseIterable`
// carrier (`Confidence`) as the binary ops, so generation is unchanged.
//
// Note on round-trip — HISTORICAL, and the diagnosis in it was right.
//
// This comment used to read: "the round-trip template pairs same-signature unary
// functions combinatorially as forward/inverse candidates, so adding unary ops
// surfaces a spurious round-trip pick (`atLeastMedium` paired with `bumpUp`) —
// there's no true inverse pair here, and execution disproves it
// (measured-defaultFails)."
//
// That named the defect exactly, and worked around it by documenting the false
// positive as expected. It is now FIXED at discovery rather than tolerated:
// `Signal.Kind.endomorphismRoundTripPair` suppresses `T -> T` × `T -> T` pairs
// with no inverse-name evidence, so the pairing no longer surfaces and verify
// no longer spends a workdir refuting it. `AlgebraicSurveyCorpusMeasuredTests`
// asserts its ABSENCE.
//
// Kept rather than deleted because the corpus deliberately still contains the
// shape — two same-signature unary ops that are not inverses — which is what
// makes it a live regression guard for that counter-signal.

extension Confidence {
    /// Clamp up to at least `.medium` — idempotent (`atLeastMedium ∘
    /// atLeastMedium == atLeastMedium`) → measured-bothPass.
    public static func atLeastMedium(_ x: Confidence) -> Confidence {
        Swift.max(x, .medium)
    }

    /// Step up one level (saturating at `.high`) — NOT idempotent
    /// (`bumpUp(bumpUp(.low)) == .high ≠ bumpUp(.low) == .medium`) → the
    /// deliberate idempotence false positive, disproven by execution.
    public static func bumpUp(_ x: Confidence) -> Confidence {
        Confidence(rawValue: Swift.min(x.rawValue + 1, Confidence.high.rawValue)) ?? x
    }
}
