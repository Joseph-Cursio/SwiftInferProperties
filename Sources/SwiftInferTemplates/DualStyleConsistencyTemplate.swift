import SwiftInferCore

/// V1.18.C — dual-style consistency template. Emits a property
/// asserting that the mutating and non-mutating siblings of a
/// `formX`/`X`, `X`/`Xing`, or `X`/`Xed` pair agree:
///
/// ```swift
/// let original = a
/// var mutated = a
/// mutated.<mutating>(<args>)
/// return mutated == a.<nonMutating>(<args>)
/// ```
///
/// **Why high-precision.** This template *requires* both members to
/// exist on the same containing type. The pairing constraint means
/// false positives only fire when a developer uses one of the curated
/// pair names for *non-paired* purposes (rare; the conventions are
/// deeply embedded in the Swift API Design Guidelines). Failures are
/// real bugs: the two implementations *should* agree, and divergence
/// is one of the highest-signal-to-noise findings PBT can surface.
///
/// **Score posture.** Every emitted suggestion clears the Likely
/// floor by construction: 30 type-shape + 40 canonical naming + 5
/// value-semantic carrier (when resolvable) = 75 → Strong tier
/// (Tier.strong threshold ≥75). Reference-type carriers drop the
/// total to 60 → Likely; mixed/unknown carriers hold at 70 → Likely.
public enum DualStyleConsistencyTemplate {

    /// V1.38.C — migrated to the Constraint Engine (PRD §20.2). The
    /// template now expresses itself as a `Constraint<DualStylePair>`
    /// via `makeConstraint(carrierKindResolver:)`. First pair-template
    /// migrated (Commutativity / Monotonicity / Associativity /
    /// InvariantPreservation are all `Constraint<FunctionSummary>`).
    /// Behavior preserved bit-for-bit.
    public static func suggest(
        for pair: DualStylePair,
        carrierKindResolver: CarrierKindResolver? = nil
    ) -> Suggestion? {
        ConstraintRunner.suggest(
            constraint: makeConstraint(carrierKindResolver: carrierKindResolver),
            subject: pair
        )
    }

    /// V1.38.C — Constraint factory. Captures the optional
    /// `carrierKindResolver` into the constraint's @Sendable closures.
    public static func makeConstraint(
        carrierKindResolver: CarrierKindResolver?
    ) -> Constraint<DualStylePair> {
        Constraint<DualStylePair>(
            templateName: "dual-style-consistency",
            appliesTo: { _ in true },   // pairing layer already gated
            signals: { pair in
                Self.accumulatedSignals(
                    for: pair,
                    carrierKindResolver: carrierKindResolver
                )
            },
            evidence: { pair in
                [
                    Self.makeEvidence(pair.mutatingMember),
                    Self.makeEvidence(pair.nonMutatingMember)
                ]
            },
            identity: Self.makeIdentity(for:),
            carrier: { $0.mutatingMember.containingTypeName },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    /// V1.38.C — preserves the pre-migration signal-accumulation order.
    static func accumulatedSignals(
        for pair: DualStylePair,
        carrierKindResolver: CarrierKindResolver?
    ) -> [Signal] {
        var signals: [Signal] = [
            typeShapeSignal(for: pair),
            namingPairSignal(for: pair)
        ]
        if let carrier = carrierKindResolver?.carrierKindSignal(
            forContainingTypeName: pair.mutatingMember.containingTypeName
        ) {
            signals.append(carrier)
        }
        if let veto = nonDeterministicVeto(for: pair) {
            signals.append(veto)
        }
        return signals
    }

    /// V1.38.C — caveat list (2 constant entries).
    static func makeCaveats() -> [String] {
        [
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer V1.18 does not verify protocol conformance — "
                + "confirm before applying.",
            "Property assumes the non-mutating member is the value-returning "
                + "counterpart of the mutating member — i.e. both implementations "
                + "describe the same logical operation. A sibling pair with the "
                + "matching name shape but divergent semantics will fail at "
                + "sampling time."
        ]
    }

    /// Canonical hash input per PRD §7.5: `template ID | container.mutating
    /// signature | container.nonMutating signature`. Halves are sorted
    /// lexicographically so two pairs surfaced from different scan orders
    /// hash identically.
    private static func makeIdentity(for pair: DualStylePair) -> SuggestionIdentity {
        let mutSig = IdempotenceTemplate.canonicalSignature(of: pair.mutatingMember)
        let nonMutSig = IdempotenceTemplate.canonicalSignature(of: pair.nonMutatingMember)
        let sorted = [mutSig, nonMutSig].sorted()
        return SuggestionIdentity(
            canonicalInput: "dual-style-consistency|" + sorted.joined(separator: "|")
        )
    }

    // MARK: - Signals

    private static func typeShapeSignal(for pair: DualStylePair) -> Signal {
        let container = pair.mutatingMember.containingTypeName ?? "?"
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Dual-style shape: \(container).\(pair.mutatingMember.name) "
                + "(mutating) ↔ \(container).\(pair.nonMutatingMember.name) "
                + "-> \(pair.nonMutatingMember.returnTypeText ?? "?")"
        )
    }

    private static func namingPairSignal(for pair: DualStylePair) -> Signal {
        let detail: String
        switch pair.rule {
        case .activeToPresentParticiple:
            detail = "Active / present-participle dual-style pair: "
                + "'\(pair.mutatingMember.name)' / '\(pair.nonMutatingMember.name)'"

        case .activeToPastParticiple:
            detail = "Active / past-participle dual-style pair: "
                + "'\(pair.mutatingMember.name)' / '\(pair.nonMutatingMember.name)'"

        case .formPrefixToBare:
            detail = "form-prefix / bare dual-style pair: "
                + "'\(pair.mutatingMember.name)' / '\(pair.nonMutatingMember.name)'"

        case .projectVocabulary:
            detail = "Project-vocabulary dual-style pair: "
                + "'\(pair.mutatingMember.name)' / '\(pair.nonMutatingMember.name)'"
        }
        return Signal(kind: .exactNameMatch, weight: 40, detail: detail)
    }

    private static func nonDeterministicVeto(for pair: DualStylePair) -> Signal? {
        let mutCalls = pair.mutatingMember.bodySignals.nonDeterministicAPIsDetected
        let nonMutCalls = pair.nonMutatingMember.bodySignals.nonDeterministicAPIsDetected
        let both = Array(Set(mutCalls).union(nonMutCalls)).sorted()
        guard !both.isEmpty else { return nil }
        return Signal(
            kind: .nonDeterministicBody,
            weight: Signal.vetoWeight,
            detail: "Non-deterministic API in dual-style pair body: "
                + "\(both.joined(separator: ", "))"
        )
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
        for pair: DualStylePair,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let mutEvidence = makeEvidence(pair.mutatingMember)
        let nonMutEvidence = makeEvidence(pair.nonMutatingMember)
        whySuggested.append(
            "\(mutEvidence.displayName) \(mutEvidence.signature)"
                + " — \(mutEvidence.location.file):\(mutEvidence.location.line)"
        )
        whySuggested.append(
            "\(nonMutEvidence.displayName) \(nonMutEvidence.signature)"
                + " — \(nonMutEvidence.location.file):\(nonMutEvidence.location.line)"
        )
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        let caveats: [String] = [
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer V1.18 does not verify protocol conformance — "
                + "confirm before applying.",
            "Property assumes the non-mutating member is the value-returning "
                + "counterpart of the mutating member — i.e. both implementations "
                + "describe the same logical operation. A sibling pair with the "
                + "matching name shape but divergent semantics will fail at "
                + "sampling time."
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
