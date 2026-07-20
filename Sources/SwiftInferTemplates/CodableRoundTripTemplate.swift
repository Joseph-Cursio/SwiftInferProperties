import SwiftInferCore

/// The **codable-round-trip** law: a type with a *hand-written* `Codable`
/// conformance owes `decode(encode(x)) == x` through a concrete coder.
///
/// Motivated by the swift-asn1 signed-integer bug (`decode(encode(128)) ==
/// -128`) surfaced in the Apple-libraries backtest (see
/// `docs/backtest-codable-roundtrip-pressuretest.md`). The round-trip law is
/// squarely in scope, but the tool's `(T) -> U` / `(U) -> T` pairing never fires
/// on a coder-mediated codec: `func encode(to: Encoder)` returns `Void` and
/// `init(from: Decoder)` consumes a `Decoder`, so there is no type-symmetric
/// encode/decode pair to match. This template recognizes the pair *structurally*
/// at the type level instead.
///
/// **The custom-conformance gate is automatic.** A synthesized `Codable`
/// conformance emits no source `encode(to:)` / `init(from:)` — the compiler
/// generates them, so they never appear in the AST the scanner walks. The
/// scanner therefore only ever sees *hand-written* halves, which is exactly the
/// bug-prone subset worth verifying (a human wrote the codec and can get it
/// wrong). The synthesized-`Codable` flood — every `Codable` type in existence,
/// the Daikon trap — never materializes.
///
/// **Tier: Likely, not Strong.** A custom codec is *intended* to round-trip but
/// is not *definitionally* an inverse pair — it may be deliberately lossy,
/// versioned, or migration-shaped. It is a candidate to verify, not a fact.
///
/// **Framework coders stay a boundary.** DER (`serialize(into: inout
/// DER.Serializer)`), protobuf, and other library coders have no generic verify
/// harness and are not recognized here — only the standard-library `Codable`
/// shape, whose round-trip verifies through `JSONEncoder` / `JSONDecoder`.
public enum CodableRoundTripTemplate {

    /// One suggestion per type that declares BOTH a custom `encode(to: Encoder)`
    /// (a scanned `FunctionSummary`) AND a custom `init(from: Decoder)` (captured
    /// on `TypeDecl.initializers`). The decode-side gate is applied here — a type
    /// with only one custom half is not a round-trip candidate.
    public static func suggestions(
        typeDecls: [TypeDecl],
        summaries: [FunctionSummary]
    ) -> [Suggestion] {
        let decodeTypes = typesWithCustomDecode(typeDecls)
        guard !decodeTypes.isEmpty else { return [] }
        var result: [Suggestion] = []
        for summary in summaries where isCustomEncode(summary) {
            guard let type = summary.containingTypeName, decodeTypes.contains(type) else { continue }
            if let suggestion = ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary) {
                result.append(suggestion)
            }
        }
        return result
    }

    /// Names of types declaring a custom `init(from decoder: Decoder)` — a
    /// single-parameter initializer labelled `from` whose type names a
    /// `Decoder`. Merged across the type's primary body / extensions by the
    /// scanner's per-type accumulation.
    static func typesWithCustomDecode(_ typeDecls: [TypeDecl]) -> Set<String> {
        var names: Set<String> = []
        for decl in typeDecls {
            for initializer in decl.initializers where initializer.parameters.count == 1 {
                guard let parameter = initializer.parameters.first,
                      parameter.label == "from",
                      parameter.typeName.contains("Decoder") else { continue }
                names.insert(decl.name)
            }
        }
        return names
    }

    /// A hand-written `func encode(to encoder: Encoder) [throws]` — the encode
    /// half of a custom `Codable` conformance: named `encode`, `Void`-returning,
    /// a single `to`-labelled parameter naming an `Encoder`, instance (not
    /// static), not an operator.
    static func isCustomEncode(_ summary: FunctionSummary) -> Bool {
        guard summary.name == "encode",
              !summary.isStatic,
              summary.containingTypeName != nil,
              isVoidReturn(summary.returnTypeText),
              summary.parameters.count == 1,
              let parameter = summary.parameters.first,
              parameter.label == "to",
              !parameter.isInout,
              parameter.typeText.contains("Encoder") else {
            return false
        }
        return true
    }

    private static func isVoidReturn(_ text: String?) -> Bool {
        guard let text else { return true }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed == "Void" || trimmed == "()" || trimmed.isEmpty
    }

    static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "codable-round-trip",
            appliesTo: Self.isCustomEncode,
            signals: { summary in
                [
                    Signal(
                        // Reuses `.exactNameMatch` (as the codec-init pairing
                        // does) rather than minting a SignalKind case — the
                        // signal IS a named encode/decode structural match.
                        kind: .exactNameMatch,
                        weight: 50,
                        detail: "`\(summary.containingTypeName ?? "")` declares a custom `Codable` "
                            + "conformance (hand-written `encode(to:)` + `init(from:)`) — an "
                            + "intended round-trip: `decode(encode(x)) == x`"
                    )
                ]
            },
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "codable-round-trip|\(summary.containingTypeName ?? "")|"
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { $0.containingTypeName },
            caveats: { _ in Self.makeCaveats() },
            generators: { _ in [] }
        )
    }

    static func makeCaveats() -> [String] {
        [
            "A custom `Codable` conformance is INTENDED to round-trip, but is not guaranteed to: a "
                + "codec may be deliberately LOSSY (drops a computed / cached field), VERSIONED, or "
                + "MIGRATION-shaped (decodes an old layout into a new one). Those are findings to "
                + "confirm, not necessarily bugs — but a codec that means to be lossless and isn't is "
                + "exactly the swift-asn1 `decode(encode(128)) == -128` class of bug.",
            "The round-trip is COORDINATE-relative: it holds under the CONCRETE coder the verifier "
                + "uses (`JSONEncoder` / `JSONDecoder`). A type that round-trips under JSON may not "
                + "under a different coder if `encode(to:)` / `init(from:)` assume a specific "
                + "container shape; and `Date` / `Data` / floating-point fields depend on the "
                + "coder's encoding strategy. `Double` / `Float` fields holding NaN or Infinity are "
                + "not JSON-representable and will fail the round-trip spuriously.",
            "Verifying this needs the type to be `Equatable` (to compare `decode(encode(x))` against "
                + "`x`) and generatable. A non-`Equatable` custom-`Codable` type still surfaces here "
                + "but is not measured-verifiable without a hand-written equality."
        ]
    }
}
