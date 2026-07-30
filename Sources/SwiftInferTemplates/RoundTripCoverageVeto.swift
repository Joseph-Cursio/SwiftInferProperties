import SwiftInferCore

/// The coverage-veto **dispatcher** for `round-trip` — the single place that asks "does another
/// tool in the toolchain already run this law?"
///
/// Extracted from `RoundTripTemplate.swift` when adding the third arm pushed it past the
/// 400-line cap. The seam is the right one rather than an arithmetic split: the per-protocol
/// gates already live in their own files (`RoundTripStrideableVeto`, `RoundTripLosslessVeto`,
/// `RoundTripCodableShapeGate`), and this is the ordering that combines them.
///
/// **Every arm is pair-scoped, and that is the standing rule here.** A carrier-only check
/// suppresses every round-trip proposed on a conforming type — `BinaryInteger` refines
/// `Strideable`, and `Int`/`Double`/`String` all conform to `LosslessStringConvertible`. The
/// Codable arm set the precedent by calling `codableRoundTrippedType` first so it suppresses
/// only codec-shaped pairs.
extension RoundTripTemplate {

    /// V1.5.2 / V1.8.1 shape-gated coverage veto. Fires when the pair has an actual Codable
    /// encoder/decoder shape AND the carrier type conforms to `Codable` — the kit's
    /// `checkCodablePropertyLaws` already verifies the JSON round-trip. The shape gate prevents
    /// over-suppression of user-defined `(Int) -> Int` inverse pairs on Codable carriers.
    static func protocolCoverageVeto(
        for pair: FunctionPair,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        if let strideable = strideableCoverageVeto(
            for: pair, inheritedTypesByName: inheritedTypesByName
        ) {
            return strideable
        }
        // Currently unreachable — `initializerPairAdmissible` rejects the pair upstream. Placed
        // so a future relaxation of that gate meets a veto instead of recreating the
        // `Strideable` double-report. See `RoundTripLosslessVeto`.
        if let lossless = losslessStringCoverageVeto(
            for: pair, inheritedTypesByName: inheritedTypesByName
        ) {
            return lossless
        }
        guard let typeText = codableRoundTrippedType(for: pair) else {
            return nil
        }
        return ProtocolCoverageMap.coverageVetoSignal(
            forTypeText: typeText,
            inheritedTypesByName: inheritedTypesByName,
            candidateProperties: [.codableRoundTrip]
        )
    }
}
