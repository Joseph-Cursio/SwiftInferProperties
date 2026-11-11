import SwiftInferCore

// V1.43 cleanup — signals/vetoes/builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension RoundTripTemplate {

    // MARK: - Signals

    static func typeSymmetrySignal(for pair: FunctionPair) -> Signal {
        // Effective domain: the receiver type for a 0-param instance-method
        // encode (`func encode() -> String` on `Blob` reads as `Blob -> String`),
        // the explicit first parameter otherwise.
        let domain = FunctionPairing.transformationDomain(pair.forward) ?? "?"
        let codomain = pair.forward.returnTypeText ?? "?"
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Type-symmetry signature: \(domain) -> \(codomain) ↔ \(codomain) -> \(domain)"
        )
    }

    /// The second curated inverse-name channel — `exp`/`log`, `sin`/`asin`, … — which
    /// `nameSignal` does not consult because it exists for a different job (the
    /// math-forward veto carve-out). Both channels count as name evidence here.
    static func hasCanonicalInverseNames(_ pair: FunctionPair) -> Bool {
        MathForwardFunctions.isCanonicalInversePair(pair.forward.name, pair.reverse.name)
    }

    static func nameSignal(
        for pair: FunctionPair,
        vocabulary: Vocabulary
    ) -> Signal? {
        let forwardName = pair.forward.name
        let reverseName = pair.reverse.name
        // Curated takes precedence over project vocabulary so a pair
        // already in the curated list never double-fires when the project
        // happens to repeat it. Both contribute the same +40 weight per
        // PRD §4.5; only the rendered detail line distinguishes them.
        if let curated = curatedInversePairs.first(where: { tuple in
            matches(forwardName: forwardName, reverseName: reverseName, lhs: tuple.0, rhs: tuple.1)
        }) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated inverse name pair: \(curated.0)/\(curated.1)"
            )
        }
        if let projectPair = vocabulary.inversePairs.first(where: { entry in
            matches(forwardName: forwardName, reverseName: reverseName, lhs: entry.forward, rhs: entry.reverse)
        }) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Project-vocabulary inverse name pair: "
                    + "\(projectPair.forward)/\(projectPair.reverse)"
            )
        }
        if let initStem = initializerLabelStemSignal(for: pair) {
            return initStem
        }
        return nil
    }

    private static func matches(
        forwardName: String,
        reverseName: String,
        lhs: String,
        rhs: String
    ) -> Bool {
        let direct = forwardName == lhs && reverseName == rhs
        let swapped = forwardName == rhs && reverseName == lhs
        return direct || swapped
    }

    /// PRD §4.1 `+35` cross-pair signal — fires when both halves of
    /// the pair share the same non-nil `@Discoverable(group:)` value.
    /// M5.1 introduces this signal in the recognize-only mode per
    /// PRD §5.7 (no runtime dep on `PropertyLawMacro`). The detail
    /// line cites the matched group name so the §4.5 explainability
    /// block can show what the signal was scoped to.
    static func discoverableSignal(for pair: FunctionPair) -> Signal? {
        guard let group = pair.sharedDiscoverableGroup else { return nil }
        return Signal(
            kind: .discoverableAnnotation,
            weight: 35,
            detail: "Both halves carry @Discoverable(group: \"\(group)\")"
        )
    }
}
