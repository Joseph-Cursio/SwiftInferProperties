import SwiftInferCore

/// The `Strideable` coverage veto for `round-trip` — the one law the toolchain was found
/// reporting twice. Its own file, matching the sibling per-veto files and because adding it
/// pushed `RoundTripTemplate.swift` past the 400-line cap.
extension RoundTripTemplate {

    /// `distance(to:)` × `advanced(by:)` on a `Strideable` carrier — the law the kit already
    /// runs as `"Strideable.distanceRoundTrip"`.
    ///
    /// **Gated on the PAIR, not just the carrier**, mirroring the Codable veto directly above:
    /// that one calls `codableRoundTrippedType` first so it suppresses only *codec-shaped*
    /// pairs rather than every round-trip on a `Codable` type. The same discipline matters more
    /// here, because `BinaryInteger` refines `Strideable` — a carrier-only check would veto
    /// every round-trip proposed on any integer type, including genuine ones this catalog
    /// exists to surface.
    ///
    /// Both names are required. A type may define its own `distance(to:)` without conforming
    /// to `Strideable`, and then the kit does *not* run the law and we should still propose it
    /// — which is why the conformance check is not dropped in favour of the names alone.
    static func strideableCoverageVeto(
        for pair: FunctionPair,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        let names = Set([pair.forward.name, pair.reverse.name])
        guard names == ["distance", "advanced"] else { return nil }
        return ProtocolCoverageMap.coverageVetoSignal(
            forTypeText: pair.forward.containingTypeName,
            inheritedTypesByName: inheritedTypesByName,
            candidateProperties: [.strideableDistanceRoundTrip]
        )
    }
}
