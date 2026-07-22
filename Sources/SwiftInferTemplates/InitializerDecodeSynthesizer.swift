import SwiftInferCore

/// Case 7 Part 2 — synthesizes the **decode** half of a codec round-trip from a
/// struct's single-parameter initializers, so an instance-method encode
/// (`func base64EncodedString() -> String`) can pair with an
/// `init?(base64Encoded: String)`.
///
/// Initializers are never scanned as `FunctionSummary` (the scanner visits only
/// `FunctionDeclSyntax`), so without this the idiomatic *encode method /
/// `init?` decode* round-trip — the most common codec shape in Swift (Base64,
/// hex, `rawValue`, …) — is unreachable. Each single-parameter struct init
/// becomes a synthetic `paramType -> Self` summary (return type = the bare
/// `Self` so it type-matches the encode's receiver domain; the failability is
/// disclosed as a caveat, not encoded in the type) marked `isInitializer`, and
/// merged **only** into the round-trip pairing input — never the general
/// per-summary template pass — so no other template ever sees it.
///
/// The synthetic name is the init's **argument label** (`base64Encoded`), which
/// `RoundTripTemplate`'s label-stem signal matches against the encode method's
/// name (`base64EncodedString` contains `base64Encoded`) to lift a genuine codec
/// pair to the default tier.
public enum InitializerDecodeSynthesizer {

    /// One synthetic decode summary per single-parameter initializer of every
    /// `struct` in `typeDecls`. Multi-parameter inits (`Point(x:y:)`) are a
    /// memberwise constructor, not a decode, and are skipped.
    public static func summaries(from typeDecls: [TypeDecl]) -> [FunctionSummary] {
        var result: [FunctionSummary] = []
        for decl in typeDecls where decl.kind == .struct {
            for initializer in decl.initializers where initializer.parameters.count == 1 {
                guard let parameter = initializer.parameters.first else { continue }
                result.append(
                    FunctionSummary(
                        name: parameter.label ?? "init",
                        parameters: [
                            Parameter(
                                label: parameter.label,
                                internalName: "value",
                                typeText: parameter.typeName,
                                isInout: false
                            )
                        ],
                        returnTypeText: decl.name,
                        isThrows: initializer.isThrowing,
                        isAsync: false,
                        isMutating: false,
                        isStatic: false,
                        location: decl.location,
                        containingTypeName: decl.name,
                        bodySignals: .empty,
                        isInitializer: true
                    )
                )
            }
        }
        return result
    }
}

extension RoundTripTemplate {

    /// Case 7 Part 2 — a codec whose decode is an **initializer**: the init's
    /// argument label (carried as the synthetic summary's name) names the
    /// encoded representation, and the encode method is named after it —
    /// `base64EncodedString` contains `base64Encoded`, `toHexString` contains
    /// `hex`, `rawValue` equals `rawValue`. A case-insensitive substring match
    /// of that label against the encode's name is the codec signal for an
    /// init-derived pair. Gated to `isInitializer` so it never fires on an
    /// ordinary function pair.
    static func initializerLabelStemSignal(for pair: FunctionPair) -> Signal? {
        let initHalf: FunctionSummary
        let encodeHalf: FunctionSummary
        if pair.forward.isInitializer {
            initHalf = pair.forward
            encodeHalf = pair.reverse
        } else if pair.reverse.isInitializer {
            initHalf = pair.reverse
            encodeHalf = pair.forward
        } else {
            return nil
        }
        let label = initHalf.name
        // Same admission predicate `FunctionPairing` gates the pair on, so the
        // filter and this +40 signal can't drift: an unlabelled init (`init(_:)`)
        // synthesizes to the bare name "init" (no stem), a <3-char label is too
        // short, and the encode name must embed the label case-insensitively.
        guard FunctionPairing.initializerLabelStemMatches(label: label, encodeName: encodeHalf.name) else {
            return nil
        }
        return Signal(
            kind: .exactNameMatch,
            weight: 40,
            detail: "Codec initializer label match: '\(encodeHalf.name)' encodes the '\(label)' "
                + "representation that `init(\(label):)` decodes"
        )
    }
}
