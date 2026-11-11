import SwiftInferCore

/// The **endomorphism** counter-signal for `round-trip` — `T -> T` paired with `T -> T`.
///
/// Its own file, matching the sibling per-counter files (`RoundTripDirectionLabelCounter`,
/// `RoundTripDomainMarkerCounter`, `RoundTripAsymmetricLabelCounter`), and because adding it
/// pushed `RoundTripTemplate.swift` past the 400-line cap.
extension RoundTripTemplate {

    // A "reciprocal labels" channel was tried here and REMOVED, because the codebase had
    // already measured it and reached the opposite conclusion.
    //
    // The reasoning was: `minimumCapacity(forScale:)` ↔ `scale(forCapacity:)` names its
    // counterpart in each direction, so the labels vouch for the pair being inverse. That is
    // wrong, and `DomainMarkerLabels.curated` says so — it contains exactly `forScale` and
    // `forCapacity`, added in cycle-11 precisely to SUPPRESS these pairs: *"all `Int -> Int
    // ↔ Int -> Int` shapes that pass typeSymmetry but cross domains semantically."*
    // Reciprocal labels mark a cross-domain CONVERSION, not an inversion. Capacity and scale
    // are different quantities; converting between them round-trips only by accident of
    // rounding.
    //
    // So the endomorphism counter and the cycle-11 domain-marker counter agree, and the
    // channel would have exempted the exact pairs cycle-11 exists to catch.

    /// `-30` when both halves map a type to itself and nothing but the shape matched.
    ///
    /// Cancels `typeSymmetrySignal`'s +30 exactly rather than merely offsetting it: the
    /// claim that signal makes — *"these two signatures oppose"* — is simply untrue of two
    /// endomorphisms, so the honest arithmetic is to take it back, not to discount it. A
    /// pair with any other corroboration (a docstring, a `@discoverable` marker) can still
    /// clear the floor on that evidence alone, which is the right outcome: the shape was
    /// never the reason.
    static func endomorphismCounterSignal(for pair: FunctionPair) -> Signal? {
        guard let forwardDomain = FunctionPairing.transformationDomain(pair.forward),
              let forwardCodomain = pair.forward.returnTypeText,
              let reverseDomain = FunctionPairing.transformationDomain(pair.reverse),
              let reverseCodomain = pair.reverse.returnTypeText else {
            return nil
        }
        let normalize = { (text: String) in text.trimmingCharacters(in: .whitespaces) }
        guard normalize(forwardDomain) == normalize(forwardCodomain),
              normalize(reverseDomain) == normalize(reverseCodomain) else {
            return nil
        }
        return Signal(
            kind: .endomorphismRoundTripPair,
            weight: -30,
            detail: "Both halves are `\(normalize(forwardDomain)) -> "
                + "\(normalize(forwardCodomain))`, so they do not OPPOSE — two "
                + "endomorphisms over one type are not an inverse pair, and "
                + "`\(pair.reverse.name)(\(pair.forward.name)(x)) == x` is false for almost "
                + "any such couple. A round-trip needs `A -> B` against `B -> A`, or an "
                + "inverse NAME pair (base64 `encode`/`decode` is a real same-type "
                + "round-trip, and its curated name carries it)"
        )
    }
}
