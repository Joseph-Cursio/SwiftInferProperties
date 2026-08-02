import SwiftInferCore

/// The `LosslessStringConvertible` coverage veto for `round-trip`.
///
/// **This one guards a door that is currently locked**, and that is deliberate rather than an
/// oversight. `initializerPairAdmissible` rejects the pair before it reaches scoring, because
/// pairing evidence for `round-trip` is name-stem overlap and an unlabelled
/// `init?(_ description: String)` synthesizes to the bare name `"init"` with no stem to match.
/// So no suggestion exists for this to suppress today.
///
/// It exists because the study twice filed that gate as a *reach gap* with "relax the gate" as
/// the implied fix — and relaxing it would have made `discover` propose a law PropertyLawKit
/// already runs (`"LosslessStringConvertible.roundTrip"`), which is precisely the `Strideable`
/// double-report found and fixed the same day. The guard is placed now, while the reasoning is
/// on the record, so that a future relaxation meets a veto rather than recreating the defect.
extension RoundTripTemplate {

    /// The parse half's synthesized names. An unlabelled `init` becomes `"init"`; a labelled
    /// one becomes its stem, and `LosslessStringConvertible`'s requirement is unlabelled.
    static let losslessParseNames: Set<String> = ["init"]

    /// The print half. `LosslessStringConvertible` refines `CustomStringConvertible`, so the
    /// law is stated against `description` — `debugDescription` is a different member with no
    /// round-trip requirement attached, and is deliberately not matched.
    static let losslessPrintNames: Set<String> = ["description"]

    /// `init?(_ description: String)` × `description` on a `LosslessStringConvertible` carrier
    /// — the law the kit runs as `"LosslessStringConvertible.roundTrip"`.
    ///
    /// Pair-scoped for the same reason as the `Strideable` veto: the conformance alone must not
    /// suppress every round-trip proposed on a conforming type. `Int`, `Double` and `String`
    /// all conform, and they carry genuine unrelated round-trips this catalog exists to find.
    static func losslessStringCoverageVeto(
        for pair: FunctionPair,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        let names = Set([pair.forward.name, pair.reverse.name])
        guard names.count == 2,
              !names.isDisjoint(with: losslessParseNames),
              !names.isDisjoint(with: losslessPrintNames) else { return nil }
        return ProtocolCoverageMap.assumedCoverageSignal(
            forTypeText: pair.forward.containingTypeName,
            inheritedTypesByName: inheritedTypesByName,
            candidateProperties: [.losslessStringRoundTrip]
        )
    }
}
