import SwiftInferCore

/// V1.8.1 — Codable encoder/decoder shape gate for
/// `RoundTripTemplate.protocolCoverageVeto(...)`.
///
/// Hosts `codableRoundTrippedType(for:)` and `codableCodecFormats` as
/// a `RoundTripTemplate` extension. Split out of `RoundTripTemplate.swift`
/// for the SwiftLint 400-line file budget per the V1.7.1
/// `StdlibConformances.swift` split precedent.
///
/// **Cycle-5 priority #1.** Tightens V1.5.2's unconditional Codable
/// veto on round-trip suggestions so the veto fires only on pairs
/// whose forward/reverse signatures actually match a Codable
/// encoder/decoder shape (`(T) -> Codec` ↔ `(Codec) -> T` for
/// `Codec ∈ {Data, String}`). Closes the cycle-4 over-suppression
/// finding: 22 OrderedCollections suggestions like
/// `minimumCapacity(forScale:) ↔ scale(forCapacity:)` on `(Int) -> Int`
/// were suppressed because `Int: Codable`, even though they're
/// user-defined inverse pairs by intent rather than Codable
/// round-trips.

extension RoundTripTemplate {

    /// V1.8.1 — returns the round-tripped type `T` when `pair` has a
    /// Codable encoder/decoder shape; returns `nil` for any other
    /// shape (including `(T) -> T` user-inverse pairs and
    /// `(T) -> U` non-codec pairs).
    ///
    /// **Encoder/decoder shape definition.** One side has signature
    /// `(T) -> Codec` (encoder), the other has `(Codec) -> T`
    /// (decoder), where `Codec ∈ {Data, String}` is a curated set of
    /// canonical Swift Codable wire formats. The pair-formation layer
    /// already enforces type-symmetry (`T -> U` ↔ `U -> T`) so the
    /// helper only needs to check whether `U` is in the curated codec
    /// set AND `T` is *not* (otherwise `(Data) -> Data` compression
    /// pairs would falsely match — see the `(Data) -> Data` test
    /// case in `ProtocolCoverageVetoPairTests`).
    ///
    /// **Curated codec set rationale.** v1.8 includes `Data` and
    /// `String` only — the two formats Swift's `JSONEncoder` /
    /// `PropertyListEncoder` / `JSONDecoder` family produces and
    /// consumes. `[UInt8]` (raw byte array), custom typealiases for
    /// codecs (e.g., domain-specific `JSONString`), and tuple wire
    /// formats are deferred until cycle-6 sampling reveals a corpus
    /// example that warrants broadening. Textual-only matching means
    /// `Foundation.Data` written out fully won't match the bare
    /// `"Data"` key — same v1 limitation as `ProtocolCoverageMap`'s
    /// type-level docs document.
    ///
    /// **Why one helper, not two.** The pair could be oriented either
    /// way (`FunctionPairing` doesn't canonicalize encoder-as-forward).
    /// The helper checks both orientations in one pass and returns
    /// the round-tripped `T` from whichever side matches.
    static func codableRoundTrippedType(for pair: FunctionPair) -> String? {
        let forwardIn = pair.forward.parameters.first?.typeText
        let forwardOut = pair.forward.returnTypeText
        let reverseIn = pair.reverse.parameters.first?.typeText
        let reverseOut = pair.reverse.returnTypeText

        // Forward = encoder `(T) -> Codec`; Reverse = decoder `(Codec) -> T`
        if let forwardOut, codableCodecFormats.contains(forwardOut),
           forwardOut == reverseIn,                       // Codec aligns
           let forwardIn, forwardIn == reverseOut,        // T aligns
           !codableCodecFormats.contains(forwardIn) {     // T is not a codec
            return forwardIn
        }
        // Forward = decoder `(Codec) -> T`; Reverse = encoder `(T) -> Codec`
        if let forwardIn, codableCodecFormats.contains(forwardIn),
           forwardIn == reverseOut,                       // Codec aligns
           let forwardOut, forwardOut == reverseIn,       // T aligns
           !codableCodecFormats.contains(forwardOut) {    // T is not a codec
            return forwardOut
        }
        return nil
    }

    /// V1.8.1 — curated set of textual type names that count as
    /// Codable wire formats. See `codableRoundTrippedType(for:)` for
    /// rationale and v1 limitations.
    static let codableCodecFormats: Set<String> = [
        "Data", "String"
    ]
}
