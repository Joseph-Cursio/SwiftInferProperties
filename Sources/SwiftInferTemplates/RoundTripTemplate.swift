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

    /// Curated inverse-name pairs per PRD v0.3 §5.2. Project-vocabulary
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

    /// `vocabulary` is the project-extensible naming layer per PRD §4.5;
    /// the template consults `vocabulary.inversePairs` alongside the
    /// curated list. Defaults to `.empty` so M1 call sites compile
    /// unchanged.
    ///
    /// V1.5.2 — `inheritedTypesByName` feeds the protocol-coverage
    /// veto. Forward type's `: Codable` conformance (or `: Codable`
    /// inherited transitively — the curated table only lists
    /// `Codable`, not `Encodable`+`Decodable` as a pair, see the
    /// V1.5.1 ProtocolCoverageMap doc) covers `codableRoundTrip` —
    /// kit `checkCodablePropertyLaws` verifies the JSONEncoder/Decoder
    /// round-trip directly. Non-Codable round-trips (custom
    /// encode/decode on a domain type) fall through unsuppressed per
    /// the v1.5 plan open-decision #4 default.
    public static func suggest(
        for pair: FunctionPair,
        vocabulary: Vocabulary = .empty,
        inheritedTypesByName: [String: Set<String>] = [:],
        carrierKindResolver: CarrierKindResolver? = nil
    ) -> Suggestion? {
        var signals: [Signal] = [typeSymmetrySignal(for: pair)]
        if let name = nameSignal(for: pair, vocabulary: vocabulary) {
            signals.append(name)
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
        // V1.24.A — asymmetric label class mismatch counter. Closes the
        // cycle-19 finding / cycle-20-reconfirmed OC asymmetric cross-
        // pair class (`index(after:) × _minimumCapacity(forScale:)`-shape).
        if let asymmetric = asymmetricLabelClassMismatchCounterSignal(for: pair) {
            signals.append(asymmetric)
        }
        if let setAlgebra = setAlgebraShapeVeto(for: pair) {
            signals.append(setAlgebra)
        }
        // V1.22.D — stride-style label both-sides veto. Closes the
        // cycle-14-demoted Algo `endOfChunk(startingAt:) × startOfChunk
        // (endingAt:)` round-trip pick.
        if let strideStyle = strideStyleLabelCounterSignal(for: pair) {
            signals.append(strideStyle)
        }
        // V1.21.C — math-library forward-function pair veto. Suppresses
        // CM cross-product noise (forward × forward like exp × cosh)
        // while preserving the canonical-inverse anchor pairs (exp × log,
        // cos × acos, etc.) cycle-17 measured at 7/7 = 100% accept.
        if let mathForward = mathForwardFunctionPairVeto(for: pair) {
            signals.append(mathForward)
        }
        // Carrier-kind signal — keyed off the forward half's containing
        // type. The cross-type counter-signal already demotes pairs whose
        // halves disagree on container, so anchoring on `forward` is safe.
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
        let score = Score(signals: signals)
        guard score.tier != .suppressed else {
            return nil
        }
        return Suggestion(
            templateName: "round-trip",
            evidence: [makeEvidence(pair.forward), makeEvidence(pair.reverse)],
            score: score,
            generator: .m1Placeholder,
            explainability: makeExplainability(for: pair, signals: signals),
            identity: makeIdentity(for: pair),
            carrier: pair.forward.containingTypeName
        )
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

    // MARK: - Signals

    private static func typeSymmetrySignal(for pair: FunctionPair) -> Signal {
        let domain = pair.forward.parameters.first?.typeText ?? "?"
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
    /// PRD v0.4 §5.7 (no runtime dep on `PropertyLawMacro`). The detail
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
    /// different containing types (e.g. `AdjacentPairsCollection.index(after:)`
    /// paired with `Chain2Sequence.index(before:)` — both have `Index`
    /// nested member types but the `Index`es are distinct, so the round-
    /// trip property cannot type-check). Drops Score 30 → 5 (well into
    /// Suppressed) so the cross-type pair is filtered from both default-
    /// tier and `--include-possible` output.
    ///
    /// **Three exemptions** (the rule fires only when none apply):
    /// 1. **Both `containingTypeName == nil`** — top-level free-function
    ///    pair like `func encode(_:) -> Data` + `func decode(_:) -> Doc`
    ///    is a legitimate module-scope round-trip. `nil == nil` falls
    ///    through cleanly via the `!=` guard.
    /// 2. **Same `containingTypeName`** — cross-extension on the same
    ///    type (`extension Doc { encode }` + `extension Doc { decode }`)
    ///    both record `"Doc"` and pair fine.
    /// 3. **Shared `@Discoverable(group:)` annotation** — the user's
    ///    explicit grouping signal overrides the structural cross-type
    ///    rule. A `struct Encoder` and `struct Decoder` paired via
    ///    `@Discoverable(group: "codec")` is a legitimate round-trip
    ///    despite different containing types; the user has opted in
    ///    by tagging both halves.
    ///
    /// Empirical motivation: V1.4.2 cycle-1 baseline showed 673 round-
    /// trip Possible-tier hits on `swift-algorithms` (the vast majority
    /// signature-only matches across distinct `Index` member types).
    /// SemanticIndex would catch this via type resolution; this rule is
    /// a cheap pre-SemanticIndex approximation using the textual
    /// `containingTypeName` field already on `FunctionSummary`.
    private static func crossTypeRoundTripCounterSignal(
        for pair: FunctionPair
    ) -> Signal? {
        let forwardContainer = pair.forward.containingTypeName
        let reverseContainer = pair.reverse.containingTypeName
        guard forwardContainer != reverseContainer else { return nil }
        // Exemption 3: shared `@Discoverable(group:)` is the user's
        // explicit "these go together" signal — overrides the structural
        // cross-type rule. The +35 discoverableAnnotation signal already
        // captures the positive evidence; adding a -25 here would
        // double-count the cross-type concern the user already addressed.
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

    /// V1.5.2 / **V1.8.1 — shape-gated**. Fires when the pair has an
    /// actual Codable encoder/decoder shape (`(T) -> Codec` ↔
    /// `(Codec) -> T` for `Codec ∈ {Data, String}`) AND the carrier
    /// type `T` conforms to `Codable` via `inheritedTypesByName`.
    /// Kit's `checkCodablePropertyLaws(for:)` verifies the JSON
    /// round-trip directly, making the suggestion redundant when
    /// the suggestion *is* a Codable round-trip.
    ///
    /// **V1.8.1 cycle-5 tightening.** V1.5.2 fired this veto whenever
    /// `pair.forward.parameters.first?.typeText` covered
    /// `codableRoundTrip` — which over-suppressed user-defined
    /// inverse pairs on Codable carriers (the cycle-4 finding:
    /// 22 OrderedCollections suggestions like
    /// `minimumCapacity(forScale:) ↔ scale(forCapacity:)` on
    /// `(Int) -> Int` were suppressed because `Int: Codable`, not
    /// because they were Codable round-trips). The shape gate
    /// restricts the veto to pairs where the kit law actually
    /// applies — true encode/decode pairs.
    ///
    /// Non-Codable round-trip pairs and `(T) -> T` user-inverse
    /// pairs on Codable carriers fall through unsuppressed.
    /// **V1.8.1.** The shape-gate helper
    /// `codableRoundTrippedType(for:)` and the curated
    /// `codableCodecFormats` set live in
    /// `RoundTripCodableShapeGate.swift` (split for SwiftLint's
    /// 400-line file budget per the V1.7.1 split precedent).
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

    private static func makeEvidence(_ summary: FunctionSummary) -> Evidence {
        Evidence(
            displayName: displayName(for: summary),
            signature: signature(for: summary),
            location: summary.location
        )
    }

    private static func makeExplainability(
        for pair: FunctionPair,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let forwardEvidence = makeEvidence(pair.forward)
        let reverseEvidence = makeEvidence(pair.reverse)
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

    // MARK: - Display helpers

    private static func displayName(for summary: FunctionSummary) -> String {
        let labels = summary.parameters.map { ($0.label ?? "_") + ":" }.joined()
        return "\(summary.name)(\(labels))"
    }

    private static func signature(for summary: FunctionSummary) -> String {
        let paramTypes = summary.parameters.map(\.typeText).joined(separator: ", ")
        var sig = "(\(paramTypes))"
        if summary.isAsync {
            sig += " async"
        }
        if summary.isThrows {
            sig += " throws"
        }
        sig += " -> \(summary.returnTypeText ?? "Void")"
        return sig
    }
}
