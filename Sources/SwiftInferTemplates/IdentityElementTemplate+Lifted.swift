import SwiftInferCore

/// V1.19.C — `IdentityElementPair`'s lifted-mutation analogue. Pairs a
/// `LiftedTransformation` with shape `(T, X) -> T` (lifted from
/// `mutating func op(by: X)`) with an `IdentityCandidate` of type `X`.
/// The associated property: `op'(s, e) == s` for all `s: T`, where `e`
/// is the identity-shaped value of type `X`.
///
/// Canonical example from `_3_Mutating API to Property Tests.md`:
/// `incremented(c, by: 0) == c` — `Counter.increment(by: 0)` is a
/// no-op because `0` is the additive identity.
public struct LiftedIdentityElementPair: Sendable, Equatable {
    public let operation: LiftedTransformation
    public let identity: IdentityCandidate

    public init(operation: LiftedTransformation, identity: IdentityCandidate) {
        self.operation = operation
        self.identity = identity
    }
}

/// V1.19.C — pair finder for the lifted identity-element template.
/// Mirrors `IdentityElementPairing` shape but operates on
/// `[LiftedTransformation]` × `[IdentityCandidate]` instead of binary
/// `(T, T) -> T` ops. Same pre-filter posture: type-shape gate enforced
/// here, naming/coverage gates live in the per-template scorer.
public enum LiftedIdentityElementPairing {

    /// Every candidate pair `(operation, identity)` such that
    ///   - `operation`'s lifted shape is `(T, X) -> T` with `X != T`
    ///     (param-matches-carrier shapes flow through IdempotenceTemplate
    ///     instead, V1.19.B),
    ///   - `identity.typeText == X` (post-generic-stripping match),
    ///   - `identity.name` is in the curated identity-shaped set
    ///     (`zero`, `empty`, `identity`, `none`, `default`).
    /// Pairs are returned sorted by `(operation.original.file,
    /// operation.original.line, identity.file, identity.line)` so the
    /// list is deterministic.
    public static func candidates(
        in lifts: [LiftedTransformation],
        identities: [IdentityCandidate]
    ) -> [LiftedIdentityElementPair] {
        var pairs: [LiftedIdentityElementPair] = []
        for operation in lifts {
            guard let paramType = singleNonCarrierParamType(of: operation) else {
                continue
            }
            let strippedParam = CarrierKindResolver.strippingGenericParameters(paramType)
            for identity in identities where identityMatches(
                identity,
                paramType: paramType,
                strippedParam: strippedParam
            ) {
                pairs.append(LiftedIdentityElementPair(
                    operation: operation,
                    identity: identity
                ))
            }
        }
        return pairs.sorted(by: lessThan)
    }

    /// Returns the single non-carrier parameter type when the lifted
    /// operation's shape is `(T, X) -> T` with `X != T`; `nil` for any
    /// other shape (no-param, param-matches-carrier, multi-param, inout).
    private static func singleNonCarrierParamType(
        of operation: LiftedTransformation
    ) -> String? {
        let originalParams = operation.originalSummary.parameters
        guard originalParams.count == 1,
              let param = originalParams.first,
              !param.isInout,
              param.typeText != operation.carrier else {
            return nil
        }
        return param.typeText
    }

    private static func identityMatches(
        _ identity: IdentityCandidate,
        paramType: String,
        strippedParam: String
    ) -> Bool {
        guard IdentityNames.curated.contains(identity.name) else { return false }
        if identity.typeText == paramType { return true }
        let strippedIdentity = CarrierKindResolver.strippingGenericParameters(identity.typeText)
        return strippedIdentity == strippedParam
    }

    private static func lessThan(
        _ lhs: LiftedIdentityElementPair,
        _ rhs: LiftedIdentityElementPair
    ) -> Bool {
        let lhsLoc = lhs.operation.originalSummary.location
        let rhsLoc = rhs.operation.originalSummary.location
        if lhsLoc.file != rhsLoc.file {
            return lhsLoc.file < rhsLoc.file
        }
        if lhsLoc.line != rhsLoc.line {
            return lhsLoc.line < rhsLoc.line
        }
        if lhs.identity.location.file != rhs.identity.location.file {
            return lhs.identity.location.file < rhs.identity.location.file
        }
        return lhs.identity.location.line < rhs.identity.location.line
    }
}

/// V1.19.C — `IdentityElementTemplate` lift admission. Score baseline
/// 30 type-shape + 40 identity-naming + 5 valueSemanticCarrier
/// (admission gate guaranteed) + 10 liftedFromMutation = **85 → Strong**
/// on canonical numeric-identity cases (`Counter.increment(by: 0) == c`).
extension IdentityElementTemplate {

    public static func suggest(
        forLifted pair: LiftedIdentityElementPair,
        carrierKindResolver: CarrierKindResolver
    ) -> Suggestion? {
        var signals: [Signal] = [liftedTypeShapeSignal(for: pair)]
        signals.append(liftedIdentityNamingSignal(for: pair))
        if let carrier = carrierKindResolver.carrierKindSignal(
            forContainingTypeName: pair.operation.carrier
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
            templateName: "identity-element",
            evidence: [
                makeLiftedOperationEvidence(pair),
                makeLiftedIdentityEvidence(pair)
            ],
            score: score,
            generator: .m1Placeholder,
            explainability: makeLiftedExplainability(for: pair, signals: signals),
            identity: makeLiftedIdentity(for: pair),
            carrier: pair.operation.carrier
        )
    }

    // MARK: - Signals

    private static func liftedTypeShapeSignal(
        for pair: LiftedIdentityElementPair
    ) -> Signal {
        let paramType = pair.operation.originalSummary.parameters[0].typeText
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Lifted identity shape: (\(pair.operation.carrier), \(paramType)) "
                + "-> \(pair.operation.carrier) with identity \(displayedIdentity(for: pair))"
        )
    }

    private static func liftedIdentityNamingSignal(
        for pair: LiftedIdentityElementPair
    ) -> Signal {
        Signal(
            kind: .exactNameMatch,
            weight: 40,
            detail: "Curated identity-element constant: '\(displayedIdentity(for: pair))' "
                + "of type \(pair.identity.typeText)"
        )
    }

    private static func liftedFromMutationSignal(
        for pair: LiftedIdentityElementPair
    ) -> Signal {
        let labels = pair.operation.originalSummary.parameters
            .map { ($0.label ?? "_") + ":" }
            .joined()
        return Signal(
            kind: .liftedFromMutation,
            weight: 10,
            detail: "Lifted from `mutating func \(pair.operation.carrier)."
                + "\(pair.operation.originalSummary.name)(\(labels))`"
        )
    }

    private static func liftedNonDeterministicVeto(
        for pair: LiftedIdentityElementPair
    ) -> Signal? {
        guard pair.operation.originalSummary.bodySignals.hasNonDeterministicCall else {
            return nil
        }
        let calls = pair.operation.originalSummary.bodySignals
            .nonDeterministicAPIsDetected
            .joined(separator: ", ")
        return Signal(
            kind: .nonDeterministicBody,
            weight: Signal.vetoWeight,
            detail: "Non-deterministic API in body: \(calls)"
        )
    }

    private static func displayedIdentity(
        for pair: LiftedIdentityElementPair
    ) -> String {
        if let containing = pair.identity.containingTypeName {
            return "\(containing).\(pair.identity.name)"
        }
        return pair.identity.name
    }

    // MARK: - Identity

    private static func makeLiftedIdentity(
        for pair: LiftedIdentityElementPair
    ) -> SuggestionIdentity {
        let opSig = IdempotenceTemplate.canonicalSignature(of: pair.operation.originalSummary)
        let identityKey: String
        if let containing = pair.identity.containingTypeName {
            identityKey = "\(containing).\(pair.identity.name):\(pair.identity.typeText)"
        } else {
            identityKey = "\(pair.identity.name):\(pair.identity.typeText)"
        }
        return SuggestionIdentity(
            canonicalInput: "identity-element-lifted|\(opSig)|\(identityKey)"
        )
    }

    // MARK: - Evidence + explainability

    private static func makeLiftedOperationEvidence(
        _ pair: LiftedIdentityElementPair
    ) -> Evidence {
        let labels = pair.operation.originalSummary.parameters
            .map { ($0.label ?? "_") + ":" }
            .joined()
        let displayName = "\(pair.operation.carrier)."
            + "\(pair.operation.originalSummary.name)(\(labels))"
        let paramTypes = pair.operation.originalSummary.parameters
            .map(\.typeText).joined(separator: ", ")
        let signature = "mutating (\(paramTypes)) -> Void  // op'(s, e) == s where e = "
            + displayedIdentity(for: pair)
        return Evidence(
            displayName: displayName,
            signature: signature,
            location: pair.operation.originalSummary.location
        )
    }

    private static func makeLiftedIdentityEvidence(
        _ pair: LiftedIdentityElementPair
    ) -> Evidence {
        Evidence(
            displayName: displayedIdentity(for: pair),
            signature: ": \(pair.identity.typeText)",
            location: pair.identity.location
        )
    }

    private static func makeLiftedExplainability(
        for pair: LiftedIdentityElementPair,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let opEvidence = makeLiftedOperationEvidence(pair)
        let identityEvidence = makeLiftedIdentityEvidence(pair)
        whySuggested.append(
            "\(opEvidence.displayName) \(opEvidence.signature) — "
                + "\(opEvidence.location.file):\(opEvidence.location.line)"
        )
        whySuggested.append(
            "\(identityEvidence.displayName)\(identityEvidence.signature) — "
                + "\(identityEvidence.location.file):\(identityEvidence.location.line)"
        )
        whySuggested.append(pair.operation.rationale)
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        let caveats: [String] = [
            "Property assumes the identity-shaped constant `"
                + "\(displayedIdentity(for: pair))` is the algebraic identity "
                + "for the mutating method's parameter type. A name-matching "
                + "constant with non-identity semantics will fail at sampling "
                + "time.",
            "Property holds iff `\(pair.operation.carrier)` has value "
                + "semantics — the lift's `var copy = original; copy."
                + "\(pair.operation.originalSummary.name)(...)` does not "
                + "alias original's state."
        ]
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }
}
