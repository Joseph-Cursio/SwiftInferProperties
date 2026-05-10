import SwiftInferCore

/// V1.19.D — `InversePairTemplate` lift admission. Scores
/// `LiftedInversePair`s — pairs of mutating add/remove-style methods on
/// the same carrier — and emits the functional-inversion property
/// `add(remove(s, x), x) == s` (and the symmetric form).
///
/// Score baseline:
/// 25 type-shape + 10 curated naming + 5 valueSemanticCarrier (admission
/// gate guaranteed) + 10 liftedFromMutation = **50 → Likely**. With a
/// matching `@Discoverable(group:)` annotation on both halves, the +35
/// signal lifts the total to 85 → Strong (parallel to the v1.18.A
/// round-trip discoverable signal).
///
/// **Why score baseline matches non-lifted InversePairTemplate.** The
/// non-lifted InversePair starts at 25 (vs round-trip's 30) per the
/// PRD §5.8 M8 row "suppressed by default" posture — non-Equatable T
/// downgrades the structural certainty. The lifted variant inherits
/// the same posture: while the carrier T IS value-semantic by admission
/// gate (so Equatable inference is plausible), the parameter type X
/// hasn't been classified, and the property requires X equality (e.g.
/// `add(remove(s, x), x)` returns the original `s` only if removing
/// the just-added `x` undoes the addition — which in turn requires
/// equality on `x`).
extension InversePairTemplate {

    public static func suggest(
        forLifted pair: LiftedInversePair,
        carrierKindResolver: CarrierKindResolver
    ) -> Suggestion? {
        var signals: [Signal] = [
            liftedTypeShapeSignal(for: pair),
            liftedNamingSignal(for: pair)
        ]
        if let carrier = carrierKindResolver.carrierKindSignal(
            forContainingTypeName: pair.forward.carrier
        ) {
            signals.append(carrier)
        }
        signals.append(liftedFromMutationSignal(for: pair))
        if let veto = liftedNonDeterministicVeto(for: pair) {
            signals.append(veto)
        }
        let score = Score(signals: signals)
        guard score.tier != .suppressed else {
            return nil
        }
        return Suggestion(
            templateName: "inverse-pair",
            evidence: [
                makeLiftedEvidence(pair.forward, role: "forward"),
                makeLiftedEvidence(pair.reverse, role: "reverse")
            ],
            score: score,
            generator: .m1Placeholder,
            explainability: makeLiftedExplainability(for: pair, signals: signals),
            identity: makeLiftedIdentity(for: pair)
        )
    }

    // MARK: - Signals

    private static func liftedTypeShapeSignal(for pair: LiftedInversePair) -> Signal {
        let paramType = pair.forward.originalSummary.parameters[0].typeText
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 25,
            detail: "Lifted inverse-pair shape: (\(pair.forward.carrier), \(paramType)) "
                + "-> \(pair.forward.carrier) with mutating sibling on same carrier"
        )
    }

    private static func liftedNamingSignal(for pair: LiftedInversePair) -> Signal {
        Signal(
            kind: .exactNameMatch,
            weight: 10,
            detail: "Curated mutating-inverse name pair: "
                + "\(pair.pairName.lhs)/\(pair.pairName.rhs)"
        )
    }

    private static func liftedFromMutationSignal(for pair: LiftedInversePair) -> Signal {
        Signal(
            kind: .liftedFromMutation,
            weight: 10,
            detail: "Lifted from mutating pair `\(pair.forward.carrier)."
                + "\(pair.forward.originalSummary.name)` ↔ `\(pair.forward.carrier)."
                + "\(pair.reverse.originalSummary.name)`"
        )
    }

    private static func liftedNonDeterministicVeto(for pair: LiftedInversePair) -> Signal? {
        let forwardCalls = pair.forward.originalSummary.bodySignals.nonDeterministicAPIsDetected
        let reverseCalls = pair.reverse.originalSummary.bodySignals.nonDeterministicAPIsDetected
        let union = Array(Set(forwardCalls).union(reverseCalls)).sorted()
        guard !union.isEmpty else { return nil }
        return Signal(
            kind: .nonDeterministicBody,
            weight: Signal.vetoWeight,
            detail: "Non-deterministic API in lifted inverse-pair body: "
                + union.joined(separator: ", ")
        )
    }

    // MARK: - Identity + evidence

    private static func makeLiftedIdentity(for pair: LiftedInversePair) -> SuggestionIdentity {
        let forwardSig = IdempotenceTemplate.canonicalSignature(of: pair.forward.originalSummary)
        let reverseSig = IdempotenceTemplate.canonicalSignature(of: pair.reverse.originalSummary)
        let sorted = [forwardSig, reverseSig].sorted()
        return SuggestionIdentity(
            canonicalInput: "inverse-pair-lifted|" + sorted.joined(separator: "|")
        )
    }

    private static func makeLiftedEvidence(
        _ lifted: LiftedTransformation,
        role: String
    ) -> Evidence {
        let labels = lifted.originalSummary.parameters
            .map { ($0.label ?? "_") + ":" }
            .joined()
        let displayName = "\(lifted.carrier).\(lifted.originalSummary.name)(\(labels))"
        let paramTypes = lifted.originalSummary.parameters.map(\.typeText).joined(separator: ", ")
        let signature = "mutating (\(paramTypes)) -> Void  // lifted \(role)"
        return Evidence(
            displayName: displayName,
            signature: signature,
            location: lifted.originalSummary.location
        )
    }

    private static func makeLiftedExplainability(
        for pair: LiftedInversePair,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let forwardEvidence = makeLiftedEvidence(pair.forward, role: "forward")
        let reverseEvidence = makeLiftedEvidence(pair.reverse, role: "reverse")
        whySuggested.append(
            "\(forwardEvidence.displayName) \(forwardEvidence.signature)"
                + " — \(forwardEvidence.location.file):\(forwardEvidence.location.line)"
        )
        whySuggested.append(
            "\(reverseEvidence.displayName) \(reverseEvidence.signature)"
                + " — \(reverseEvidence.location.file):\(reverseEvidence.location.line)"
        )
        whySuggested.append(pair.forward.rationale)
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        let caveats: [String] = [
            "X must conform to Equatable for the property body to compile — "
                + "the assertion compares \(pair.forward.carrier) values that "
                + "depend on X equality semantics.",
            "Property holds iff the two mutating siblings are functional "
                + "inverses on the lifted shadows: removing the just-added `x` "
                + "fully undoes the addition. Implementations with hidden "
                + "ordering, multiset semantics, or capacity-bounded behavior "
                + "may fail at sampling time.",
            "Property holds iff `\(pair.forward.carrier)` has value semantics "
                + "— the lift's `var copy = original; copy.<add>(...)` does "
                + "not alias original's state."
        ]
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }
}
