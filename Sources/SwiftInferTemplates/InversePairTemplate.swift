import SwiftInferCore

/// Inverse-pair template — `f: T -> U` paired with `g: U -> T` where
/// `T` does *not* classify as `Equatable` per `EquatableResolver`
/// (M3.3). Fills the gap RoundTripTemplate (M1.4) leaves: round-trip
/// vetoes when `T` is not Equatable since its emitted property uses
/// `==`; inverse-pair surfaces the structural claim as a Possible-tier
/// informational suggestion the user can act on with a custom equality
/// witness or annotation API extension.
///
/// Necessary type pattern (PRD v0.4 §5.2 + §5.8 M8 row): the pair's
/// type shape (enforced by `FunctionPairing`) plus `T` *not*
/// classifying as `.equatable`. Equatable `T` defers to RoundTripTemplate;
/// this template only fires when the resolver returns `.notEquatable` or
/// `.unknown` for the forward param type. When no resolver is supplied
/// (test/programmatic-discovery callers that haven't threaded
/// `typeDecls` through), the template assumes "non-Equatable" so it
/// still fires — same posture as RoundTripTemplate's `vocabulary: .empty`
/// default.
///
/// Score lands in the Possible tier (20–39) per PRD v0.4 §5.8's
/// "suppressed by default" posture — type-pattern alone scores 25;
/// curated naming or project-vocabulary `inversePairs` adds 10.
/// Hidden behind `--include-possible` per the §5.8 M8 row; explicit
/// `--include-possible` exposes them. The type-flow `g(f(x))`
/// composition signal (PRD §5.3 inverse-by-usage) is *not* shipped in
/// M8.1 because `BodySignals` doesn't carry an inverse-composition
/// flag yet — `hasSelfComposition` only catches `f(f(x))`. Adding the
/// flag is a small `FunctionScanner` extension; deferred to v1.1+ per
/// the M8 plan ("the type-flow `g(f(x))` composition signal ... lands
/// once `BodySignals` surface this").
public enum InversePairTemplate {

    /// `vocabulary` is the project-extensible naming layer per PRD §4.5;
    /// the template consults `vocabulary.inversePairs` alongside the
    /// curated list shared with `RoundTripTemplate`.
    ///
    /// `equatableResolver` gates the template — `nil` defaults to "fire"
    /// so callers without corpus type-decls (tests, programmatic
    /// callers) still surface the suggestion; CLI / `discover(in:)`
    /// passes a real resolver built from the scanned `typeDecls`.
    ///
    /// V1.5.2 — `inheritedTypesByName` feeds the protocol-coverage
    /// veto. Forward type's conformance set drives the lookup;
    /// candidate properties are `additiveInverse` (covered by
    /// SignedNumeric — the kit's `checkSignedNumericPropertyLaws`
    /// verifies `a + (-a) == .zero`) + `groupInverse` (covered by kit
    /// Group — the kit's `checkGroupPropertyLaws` verifies the
    /// abstract `combine(x, x⁻¹) == .identity`). Other inverse pairs
    /// (e.g. `parse/format` on a custom Doc type) fall through
    /// unsuppressed.
    public static func suggest(
        for pair: FunctionPair,
        vocabulary: Vocabulary = .empty,
        equatableResolver: EquatableResolver? = nil,
        inheritedTypesByName: [String: Set<String>] = [:]
    ) -> Suggestion? {
        // Forward param type — `T` in the `f: T -> U` pair.
        guard let domain = pair.forward.parameters.first?.typeText else {
            return nil
        }
        // Equatable T → defer to RoundTripTemplate. `.notEquatable` and
        // `.unknown` both fire — the latter because the resolver can't
        // confirm Equatable conformance for arbitrary corpus types, and
        // the surfaced caveat in the §4.5 block tells the user why.
        if let resolver = equatableResolver,
           resolver.classify(typeText: domain) == .equatable {
            return nil
        }
        var signals: [Signal] = [typeSymmetrySignal(for: pair)]
        if let name = nameSignal(for: pair, vocabulary: vocabulary) {
            signals.append(name)
        }
        if let fpCounter = floatingPointStorageCounterSignal(for: pair) {
            signals.append(fpCounter)
        }
        if let direction = directionLabelCounterSignal(for: pair) {
            signals.append(direction)
        }
        if let setAlgebra = setAlgebraShapeVeto(for: pair) {
            signals.append(setAlgebra)
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
            templateName: "inverse-pair",
            evidence: [makeEvidence(pair.forward), makeEvidence(pair.reverse)],
            score: score,
            generator: .m1Placeholder,
            explainability: makeExplainability(for: pair, signals: signals),
            identity: makeIdentity(for: pair)
        )
    }

    /// Canonical hash input per PRD §7.5: `template ID | canonical
    /// signature A | canonical signature B`, where A and B are sorted
    /// lexicographically so the hash is orientation-agnostic. Mirrors
    /// `RoundTripTemplate.makeIdentity` so the two templates produce
    /// distinct identity hashes for the same pair (different template
    /// prefix), avoiding collision in the decisions / baseline files.
    private static func makeIdentity(for pair: FunctionPair) -> SuggestionIdentity {
        let forwardSig = IdempotenceTemplate.canonicalSignature(of: pair.forward)
        let reverseSig = IdempotenceTemplate.canonicalSignature(of: pair.reverse)
        let sorted = [forwardSig, reverseSig].sorted()
        return SuggestionIdentity(canonicalInput: "inverse-pair|" + sorted.joined(separator: "|"))
    }

    // MARK: - Signals

    private static func typeSymmetrySignal(for pair: FunctionPair) -> Signal {
        let domain = pair.forward.parameters.first?.typeText ?? "?"
        let codomain = pair.forward.returnTypeText ?? "?"
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 25,
            detail: "Type-symmetry signature: \(domain) -> \(codomain) ↔ \(codomain) -> \(domain) (non-Equatable T)"
        )
    }

    private static func nameSignal(
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

    /// V1.5.2 — fires when the forward type's existing conformances
    /// cover the inverse-pair property the template would emit.
    /// Candidate properties: `additiveInverse` (kit
    /// `checkSignedNumericPropertyLaws`) + `groupInverse` (kit
    /// `checkGroupPropertyLaws`). Inverse-pair templates on custom
    /// non-algebraic types (`parse/format`, `encode/decode` on a
    /// non-Codable carrier) fall through unsuppressed because no
    /// kit-published inverse law applies.
    private static func protocolCoverageVeto(
        for pair: FunctionPair,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        ProtocolCoverageMap.coverageVetoSignal(
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
    private static func floatingPointStorageCounterSignal(
        for pair: FunctionPair
    ) -> Signal? {
        let domain = pair.forward.parameters.first?.typeText
        let codomain = pair.forward.returnTypeText
        let candidates = [domain, codomain].compactMap { $0 }
        guard candidates.contains(where: { FloatingPointStorageNames.contains($0) }) else {
            return nil
        }
        let stripped = candidates
            .first(where: { FloatingPointStorageNames.contains($0) })
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
    private static func floatingPointAdvisory(for pair: FunctionPair) -> String? {
        let domain = pair.forward.parameters.first?.typeText
        let codomain = pair.forward.returnTypeText
        let candidates = [domain, codomain].compactMap { $0 }
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
        var caveats: [String] = [
            "Non-Equatable T means SwiftInfer cannot sample-verify the round-trip — "
                + "the suggestion is name-and-type-pattern only.",
            "TestLifter corroboration not yet wired (gated on TestLifter M1).",
            "Possible-tier by default — escalation requires a custom equality witness "
                + "or annotation API extension.",
            "If T conforms to Equatable, RoundTripTemplate (M1.4) handles this case "
                + "with stronger evidence — inverse-pair only fires when "
                + "EquatableResolver returns .notEquatable or .unknown for T."
        ]
        if let fpCaveat = floatingPointAdvisory(for: pair) {
            caveats.append(fpCaveat)
        }
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }

    // MARK: - Display helpers (mirrors RoundTripTemplate)

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
