import SwiftInferCore

/// `RoundTripTemplate`'s cross-type counter and its codec-carrier exemption.
///
/// Split out of `RoundTripTemplate.swift` to keep that file under the 400-line
/// cap. The counter is a self-contained calibration decision with its own
/// measurement history, so it reads better on its own anyway.
extension RoundTripTemplate {

    /// V1.4.3b — fires when forward and reverse functions belong to
    /// distinct containing types. Drops Score 30 → 5 (Suppressed).
    /// Four exemptions: both containers nil (free-function pair), same
    /// container (cross-extension on the same type), shared
    /// `@Discoverable(group:)` annotation (user's explicit grouping
    /// overrides the structural rule), or complementary codec carriers.
    /// Empirical motivation: V1.4.2 cycle-1 baseline showed 673 round-trip
    /// Possible-tier hits on `swift-algorithms` from cross-type `Index`
    /// member mismatches.
    ///
    /// The counter still earns its keep — re-measured for
    /// `docs/measurements/parsing-catalog-gap.md` §3b, it suppresses 1,380 cross-type
    /// pairs across the reference corpora and all but a handful are noise.
    /// Exemption 4 carves out the one shape that is not: a codec whose two
    /// halves live in a `Loader`/`Writer`-style pair of types, which is how
    /// serializer round trips are actually laid out. See `CodecCarrierPairing`
    /// for why the gate is the *role noun* and not the shared stem — a stem
    /// test would have re-admitted the whole flood.
    static func crossTypeRoundTripCounterSignal(
        for pair: FunctionPair
    ) -> Signal? {
        let forwardContainer = pair.forward.containingTypeName
        let reverseContainer = pair.reverse.containingTypeName
        guard forwardContainer != reverseContainer else { return nil }
        // Exemption 3: shared @Discoverable(group:) overrides the structural
        // cross-type rule (+35 already captures the positive evidence).
        if let forwardGroup = pair.forward.discoverableGroup,
           let reverseGroup = pair.reverse.discoverableGroup,
           forwardGroup == reverseGroup {
            return nil
        }
        // Exemption 4: the two carriers name mutually inverse codec roles.
        // The counter's reason — "cannot type-check across distinct containing
        // types" — is a codegen concern, and for a codec split it is wrong:
        // the round trip is DESIGNED to span the two types.
        if let forwardContainer, let reverseContainer,
           CodecCarrierPairing.areComplementary(forwardContainer, reverseContainer) {
            return nil
        }
        let forwardLabel = forwardContainer ?? "<top-level>"
        let reverseLabel = reverseContainer ?? "<top-level>"
        return Signal(
            kind: .crossTypeRoundTripPair,
            weight: -25,
            detail: "Cross-type round-trip pair: forward in \(forwardLabel), "
                + "reverse in \(reverseLabel) — property cannot type-check "
                + "across distinct containing types (cycle-1 calibration)"
        )
    }
}
