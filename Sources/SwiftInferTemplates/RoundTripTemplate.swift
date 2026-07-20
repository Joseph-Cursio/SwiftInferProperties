import SwiftInferCore

/// Round-trip template — `f: T -> U` paired with `g: U -> T` where
/// `g(f(t)) == t`. Cross-function: consumes `FunctionPair`s produced by
/// `FunctionPairing` rather than individual summaries.
///
/// Necessary type pattern (PRD §5.2): the pair's type shape (enforced by
/// `FunctionPairing`'s type filter) plus `T: Equatable`. M1.4 cannot
/// verify protocol conformance — see the always-rendered Equatable
/// caveat in the §4.5 explainability block.
///
/// Counter-signals: non-Equatable `T` (-∞ veto, structurally untestable —
/// can only be applied at M3+ once semantic resolution lands); type-flow
/// detection of non-deterministic API calls in *either* body is a -∞
/// veto (Appendix B.3 + B.4).
public enum RoundTripTemplate {

    /// Curated inverse-name pairs per PRD §5.2. Project-vocabulary
    /// extension (§4.5's `inversePairs` from `vocabulary.json`) lands at
    /// M2; M1.4 ships the curated list, exact-match in either order.
    public static let curatedInversePairs: [(String, String)] = [
        ("encode", "decode"),
        ("serialize", "deserialize"),
        ("compress", "decompress"),
        ("encrypt", "decrypt"),
        ("parse", "format"),
        ("push", "pop"),
        ("insert", "remove"),
        ("open", "close"),
        ("marshal", "unmarshal"),
        ("pack", "unpack"),
        ("lock", "unlock")
    ]

    /// `vocabulary` extends the curated list with project-defined inverse
    /// pairs (PRD §4.5). `inheritedTypesByName` feeds the V1.5.2
    /// protocol-coverage veto: `: Codable` conformance covers
    /// `codableRoundTrip` (kit's `checkCodablePropertyLaws` verifies
    /// JSONEncoder/Decoder round-trip directly). V1.39.A migrated this
    /// to the Constraint Engine (PRD §20.2); behavior preserved.
    public static func suggest(
        for pair: FunctionPair,
        vocabulary: Vocabulary = .empty,
        inheritedTypesByName: [String: Set<String>] = [:],
        carrierKindResolver: CarrierKindResolver? = nil
    ) -> Suggestion? {
        ConstraintRunner.suggest(
            constraint: makeConstraint(
                vocabulary: vocabulary,
                inheritedTypesByName: inheritedTypesByName,
                carrierKindResolver: carrierKindResolver
            ),
            subject: pair
        )
    }

    /// V1.39.A — Constraint factory.
    public static func makeConstraint(
        vocabulary: Vocabulary,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver?
    ) -> Constraint<FunctionPair> {
        Constraint<FunctionPair>(
            templateName: "round-trip",
            appliesTo: { _ in true },   // pre-migration unconditionally accepted shape
            signals: { pair in
                Self.accumulatedSignals(
                    for: pair,
                    vocabulary: vocabulary,
                    inheritedTypesByName: inheritedTypesByName,
                    carrierKindResolver: carrierKindResolver
                )
            },
            evidence: { pair in
                [pair.forward.inferenceEvidence, pair.reverse.inferenceEvidence]
            },
            identity: Self.makeIdentity(for:),
            carrier: { $0.forward.containingTypeName },
            caveats: { Self.makeCaveats(for: $0) }
        )
    }

    /// V1.39.A — preserves the pre-migration signal-accumulation order.
    /// Split into name- and veto-side helpers to keep each function
    /// within SwiftLint's cyclomatic_complexity cap.
    static func accumulatedSignals(
        for pair: FunctionPair,
        vocabulary: Vocabulary,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver?
    ) -> [Signal] {
        var signals: [Signal] = [typeSymmetrySignal(for: pair)]
        signals.append(contentsOf: nameSideSignals(for: pair, vocabulary: vocabulary))
        signals.append(contentsOf: vetoSideSignals(
            for: pair,
            inheritedTypesByName: inheritedTypesByName,
            carrierKindResolver: carrierKindResolver
        ))
        return signals
    }

    private static func nameSideSignals(
        for pair: FunctionPair,
        vocabulary: Vocabulary
    ) -> [Signal] {
        var signals: [Signal] = []
        if let name = nameSignal(for: pair, vocabulary: vocabulary) {
            signals.append(name)
        }
        if let docstring = docstringCorroborationSignal(for: pair) {
            signals.append(docstring)
        }
        if let discoverable = discoverableSignal(for: pair) {
            signals.append(discoverable)
        }
        if let crossType = crossTypeRoundTripCounterSignal(for: pair) {
            signals.append(crossType)
        }
        if let direction = directionLabelCounterSignal(for: pair) {
            signals.append(direction)
        }
        if let domainMarker = domainMarkerCounterSignal(for: pair) {
            signals.append(domainMarker)
        }
        if let asymmetric = asymmetricLabelClassMismatchCounterSignal(for: pair) {
            signals.append(asymmetric)
        }
        return signals
    }

    private static func vetoSideSignals(
        for pair: FunctionPair,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver?
    ) -> [Signal] {
        var signals: [Signal] = []
        if let setAlgebra = setAlgebraShapeVeto(for: pair) {
            signals.append(setAlgebra)
        }
        if let strideStyle = strideStyleLabelCounterSignal(for: pair) {
            signals.append(strideStyle)
        }
        if let mathForward = mathForwardFunctionPairVeto(for: pair) {
            signals.append(mathForward)
        }
        if let carrier = carrierKindResolver?.carrierKindSignal(
            forContainingTypeName: pair.forward.containingTypeName
        ) {
            signals.append(carrier)
        }
        if let veto = nonDeterministicVeto(for: pair) {
            signals.append(veto)
        }
        if let coverageVeto = protocolCoverageVeto(
            for: pair,
            inheritedTypesByName: inheritedTypesByName
        ) {
            signals.append(coverageVeto)
        }
        return signals
    }

    /// V1.39.A — caveat list (2 constant entries).
    static func makeCaveats(for pair: FunctionPair) -> [String] {
        var caveats = [
            "Throws on either side narrows the property's domain to the success set "
                + "of the inner function; a generator that produces values outside that "
                + "set will surface false-positive failures (Appendix B.4).",
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer M1 does not verify protocol conformance — confirm before applying."
        ]
        if pair.forward.isInitializer || pair.reverse.isInitializer {
            caveats.append(
                "DECODE IS AN INITIALIZER, so the round trip is DIRECTIONAL: the law is "
                    + "`Type(<label>: x.encode()) == x` over the VALUE domain, not the other way — "
                    + "`encode` applied to an arbitrary encoded string need not round-trip, because "
                    + "not every string is a valid encoding. For a FAILABLE `init?`, unwrap first: "
                    + "the decode of a freshly-encoded value must succeed and equal the original "
                    + "(`decode(encode(x)) == .some(x)`)."
            )
        }
        return caveats
    }

    /// Canonical hash input per PRD §7.5: `template ID | canonical
    /// signature A | canonical signature B`, where A and B are sorted
    /// lexicographically so the hash is orientation-agnostic. A pair
    /// produces the same identity regardless of which half
    /// `FunctionPairing` chose as `forward`.
    private static func makeIdentity(for pair: FunctionPair) -> SuggestionIdentity {
        let forwardSig = IdempotenceTemplate.canonicalSignature(of: pair.forward)
        let reverseSig = IdempotenceTemplate.canonicalSignature(of: pair.reverse)
        let sorted = [forwardSig, reverseSig].sorted()
        return SuggestionIdentity(canonicalInput: "round-trip|" + sorted.joined(separator: "|"))
    }
}

// V1.43 cleanup — signals/vetoes/builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension RoundTripTemplate {

    // MARK: - Signals

    private static func typeSymmetrySignal(for pair: FunctionPair) -> Signal {
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

    private static func nameSignal(
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
    private static func discoverableSignal(for pair: FunctionPair) -> Signal? {
        guard let group = pair.sharedDiscoverableGroup else { return nil }
        return Signal(
            kind: .discoverableAnnotation,
            weight: 35,
            detail: "Both halves carry @Discoverable(group: \"\(group)\")"
        )
    }

    /// V1.4.3b — fires when forward and reverse functions belong to
    /// distinct containing types. Drops Score 30 → 5 (Suppressed).
    /// Three exemptions: both containers nil (free-function pair), same
    /// container (cross-extension on the same type), or shared
    /// `@Discoverable(group:)` annotation (user's explicit grouping
    /// overrides the structural rule). Empirical motivation: V1.4.2
    /// cycle-1 baseline showed 673 round-trip Possible-tier hits on
    /// `swift-algorithms` from cross-type `Index` member mismatches.
    private static func crossTypeRoundTripCounterSignal(
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

    private static func nonDeterministicVeto(for pair: FunctionPair) -> Signal? {
        let forwardCalls = pair.forward.bodySignals.nonDeterministicAPIsDetected
        let reverseCalls = pair.reverse.bodySignals.nonDeterministicAPIsDetected
        let both = Array(Set(forwardCalls).union(reverseCalls)).sorted()
        guard !both.isEmpty else {
            return nil
        }
        let side = describeAffectedSide(pair: pair)
        return Signal(
            kind: .nonDeterministicBody,
            weight: Signal.vetoWeight,
            detail: "Non-deterministic API in \(side): \(both.joined(separator: ", "))"
        )
    }

    /// V1.5.2 / V1.8.1 shape-gated coverage veto. Fires when the pair
    /// has an actual Codable encoder/decoder shape AND the carrier
    /// type conforms to `Codable` — kit's `checkCodablePropertyLaws`
    /// already verifies the JSON round-trip. The shape gate prevents
    /// over-suppression of user-defined `(Int) -> Int` inverse pairs
    /// on Codable carriers. Shape helpers live in
    /// `RoundTripCodableShapeGate.swift`.
    private static func protocolCoverageVeto(
        for pair: FunctionPair,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        guard let typeText = codableRoundTrippedType(for: pair) else {
            return nil
        }
        return ProtocolCoverageMap.coverageVetoSignal(
            forTypeText: typeText,
            inheritedTypesByName: inheritedTypesByName,
            candidateProperties: [.codableRoundTrip]
        )
    }

    private static func describeAffectedSide(pair: FunctionPair) -> String {
        let forwardHas = pair.forward.bodySignals.hasNonDeterministicCall
        let reverseHas = pair.reverse.bodySignals.hasNonDeterministicCall
        switch (forwardHas, reverseHas) {
        case (true, true): return "both bodies"
        case (true, false): return "\(pair.forward.name) body"
        case (false, true): return "\(pair.reverse.name) body"
        case (false, false): return "neither body"
        }
    }

    // MARK: - Suggestion construction

    private static func makeExplainability(
        for pair: FunctionPair,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let forwardEvidence = pair.forward.inferenceEvidence
        let reverseEvidence = pair.reverse.inferenceEvidence
        whySuggested.append(
            "\(forwardEvidence.displayName) \(forwardEvidence.signature)"
                + " — \(forwardEvidence.location.file):\(forwardEvidence.location.line)"
        )
        whySuggested.append(
            "\(reverseEvidence.displayName) \(reverseEvidence.signature)"
                + " — \(reverseEvidence.location.file):\(reverseEvidence.location.line)"
        )
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        let caveats: [String] = [
            "Throws on either side narrows the property's domain to the success set "
                + "of the inner function; a generator that produces values outside that "
                + "set will surface false-positive failures (Appendix B.4).",
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer M1 does not verify protocol conformance — confirm before applying."
        ]
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }
}
