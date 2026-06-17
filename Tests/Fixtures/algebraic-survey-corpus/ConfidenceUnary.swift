// Widens the algebraic corpus to the IDEMPOTENCE family — static unary
// `(Confidence) -> Confidence` ops where `f(f(x)) == f(x)`. Same `.caseIterable`
// carrier (`Confidence`) as the binary ops, so generation is unchanged.
//
// Note on round-trip: the round-trip template pairs same-signature unary
// functions combinatorially as forward/inverse candidates, so adding unary ops
// surfaces a spurious round-trip pick (`atLeastMedium` paired with `bumpUp`) —
// there's no true inverse pair here, and execution disproves it
// (measured-defaultFails). A clean true-positive round-trip needs a dedicated
// mutual-inverse pair on its own carrier; left out to keep the corpus tight.

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
