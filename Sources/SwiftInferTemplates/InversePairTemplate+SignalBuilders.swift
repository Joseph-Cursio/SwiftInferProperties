import SwiftInferCore

// V1.43 cleanup — signals/vetoes/builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension InversePairTemplate {

    // MARK: - Signals

    static func typeSymmetrySignal(for pair: FunctionPair) -> Signal {
        let domain = pair.forward.parameters.first?.typeText ?? "?"
        let codomain = pair.forward.returnTypeText ?? "?"
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 25,
            detail: "Type-symmetry signature: \(domain) -> \(codomain) ↔ \(codomain) -> \(domain) (non-Equatable T)"
        )
    }

    static func nameSignal(
        for pair: FunctionPair,
        vocabulary: Vocabulary
    ) -> Signal? {
        let forwardName = pair.forward.name
        let reverseName = pair.reverse.name
        // Reuses `RoundTripTemplate.curatedInversePairs` — the curated
        // list applies regardless of whether T is Equatable; the
        // semantics of the inversion don't change with the codomain
        // type's value-equality story.
        if let curated = RoundTripTemplate.curatedInversePairs.first(where: { tuple in
            matches(forwardName: forwardName, reverseName: reverseName, lhs: tuple.0, rhs: tuple.1)
        }) {
            return Signal(
                kind: .exactNameMatch,
                weight: 10,
                detail: "Curated inverse name pair: \(curated.0)/\(curated.1)"
            )
        }
        if let projectPair = vocabulary.inversePairs.first(where: { entry in
            matches(forwardName: forwardName, reverseName: reverseName, lhs: entry.forward, rhs: entry.reverse)
        }) {
            return Signal(
                kind: .exactNameMatch,
                weight: 10,
                detail: "Project-vocabulary inverse pair match: "
                    + "\(projectPair.forward)/\(projectPair.reverse)"
            )
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

    /// V1.5.2 — fires when the forward type's existing conformances
    /// cover the inverse-pair property the template would emit.
    /// Candidate properties: `additiveInverse` (kit
    /// `checkSignedNumericPropertyLaws`) + `groupInverse` (kit
    /// `checkGroupPropertyLaws`). Inverse-pair templates on custom
    /// non-algebraic types (`parse/format`, `encode/decode` on a
    /// non-Codable carrier) fall through unsuppressed because no
    /// kit-published inverse law applies.
    static func assumedKitCoverage(
        for pair: FunctionPair,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        ProtocolCoverageMap.assumedCoverageSignal(
            forTypeText: pair.forward.parameters.first?.typeText,
            inheritedTypesByName: inheritedTypesByName,
            candidateProperties: [.additiveInverse, .groupInverse]
        )
    }

    /// V1.4.3 — fires when either side of the pair's parameter type
    /// is FP-storage (forward's `(T) -> U` domain T, or equivalently
    /// reverse's `(U) -> T` codomain). For inverse-pair both directions
    /// matter: `sqrt(x*x) ≠ x` for negative x, etc. Drops Score 25 → 15
    /// (Suppressed) — slightly more aggressive than assoc/comm because
    /// inverse-pair already has lower baseline (25 not 30); -10 lands
    /// in Suppressed (< 20) here. The kit-pointer in the explainability
    /// is still surfaced because the suggestion was filtered AFTER
    /// score computation, but `--include-possible` users won't see it.
    /// Acceptable trade-off: inverse-pair is rare on FP corpora and
    /// the cycle-2 approximate-equality template arm is the proper fix.
    static func floatingPointStorageCounterSignal(
        for pair: FunctionPair
    ) -> Signal? {
        let domain = pair.forward.parameters.first?.typeText
        let codomain = pair.forward.returnTypeText
        let candidates = [domain, codomain].compactMap(\.self)
        guard candidates.contains(where: { FloatingPointStorageNames.contains($0) }) else {
            return nil
        }
        let stripped = candidates
            .first { FloatingPointStorageNames.contains($0) }
            .map(FloatingPointStorageNames.strippingGenericParameters)
            ?? "?"
        return Signal(
            kind: .floatingPointStorage,
            weight: -10,
            detail: "Floating-point storage in inverse pair (T = \(stripped)) — "
                + "exact-equality round-trip is not bit-exact under IEEE 754"
        )
    }

    /// V1.4.3 — type-aware FP advisory paralleling the assoc/comm
    /// helpers. `nil` when neither side of the pair is FP-storage.
    static func floatingPointAdvisory(for pair: FunctionPair) -> String? {
        let domain = pair.forward.parameters.first?.typeText
        let codomain = pair.forward.returnTypeText
        let candidates = [domain, codomain].compactMap(\.self)
        guard let fpType = candidates.first(where: { FloatingPointStorageNames.contains($0) }) else {
            return nil
        }
        let stripped = FloatingPointStorageNames.strippingGenericParameters(fpType)
        if FloatingPointStorageNames.isKitSupported(fpType) {
            return "Pair type \(stripped) conforms to FloatingPoint. Round-trip "
                + "identity holds in principle; exact-equality auto-sampling fails on "
                + "IEEE 754 precision loss / NaN edge cases. Verify via a finite-only "
                + "generator (e.g. `Gen<Double>.double(in: -1e6...1e6)`) per "
                + "PropertyLawKit's `FloatingPointLaws.swift` posture — kit "
                + "`checkFloatingPointPropertyLaws` covers FP-specific laws (NaN, "
                + "infinity), algebraic inverse-pair needs the finite-only opt-in. "
                + "v1.5+ will surface the generator override automatically."
        }
        return "Pair type \(stripped) has IEEE 754 floating-point storage. Round-"
            + "trip identity holds in principle; exact-equality auto-sampling fails on "
            + "rounding / NaN edge cases. Verify via a finite-only generator (e.g. "
            + "`Gen<Double>.double(in: -1e6...1e6)` lifted into \(stripped)) per "
            + "PropertyLawKit's `FloatingPointLaws.swift` tolerance posture. v1.5+ "
            + "will surface the generator override automatically."
    }

    // MARK: - Suggestion construction

    static func makeExplainability(
        for pair: FunctionPair,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let forwardEvidence = pair.forward.inferenceEvidence
        let reverseEvidence = pair.reverse.inferenceEvidence
        whySuggested.append(
            "\(forwardEvidence.displayName) \(forwardEvidence.signature)"
                + " — \(forwardEvidence.location)"
        )
        whySuggested.append(
            "\(reverseEvidence.displayName) \(reverseEvidence.signature)"
                + " — \(reverseEvidence.location)"
        )
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        var caveats: [String] = [
            "Non-Equatable T means SwiftInfer cannot sample-verify the round-trip — "
                + "the suggestion is name-and-type-pattern only.",
            "TestLifter corroboration not yet wired (gated on TestLifter M1).",
            "Possible-tier by default — escalation requires a custom equality witness "
                + "or annotation API extension.",
            "If T conforms to Equatable, RoundTripTemplate (M1.4) handles this case "
                + "with stronger evidence — inverse-pair only fires when "
                + "EquatableResolver returns .notEquatable or .unknown for T.",
        ]
        if let fpCaveat = floatingPointAdvisory(for: pair) {
            caveats.append(fpCaveat)
        }
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }
}
