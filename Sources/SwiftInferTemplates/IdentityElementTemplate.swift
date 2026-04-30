import SwiftInferCore

/// Identity-element template — a binary op `f: (T, T) -> T` together with
/// an identity-shaped constant `e: T` such that `f(t, e) == t` and
/// `f(e, t) == t` for all `t`. Cross-function: consumes
/// `IdentityElementPair`s produced by `IdentityElementPairing` rather than
/// individual summaries.
///
/// Necessary type pattern (PRD §5.2):
///   - operation matches the `(T, T) -> T` shape (same as commutativity /
///     associativity), enforced by the pairing layer;
///   - identity candidate's `typeText` equals `T`, also enforced by the
///     pairing layer;
///   - operation is not `mutating`, no parameter is `inout`, return type
///     is non-`Void`. (All of these are pre-filtered by the pairer.)
///
/// Naming signal (+40 per PRD §4 / §5.2): identity-element pairing is
/// itself the strongest naming signal — a `(T, T) -> T` op with a
/// same-typed `T.empty` / `T.zero` / `T.identity` / `T.none` /
/// `T.default` constant in scope is exactly the priority-1 monoid pattern
/// from v0.2 §5.2. The pairer only emits pairs where the identity's name
/// is in the curated list (§5.2 priority 1), so every emitted pair earns
/// the +40 by construction.
///
/// Type-flow signal (+20 per PRD §5.3): accumulator-with-empty-seed —
/// fires when the operation's name appears in the corpus-wide
/// `opsWithIdentitySeed` set, i.e. some `.reduce(<identity-shape>, op)`
/// call site uses our op with an identity-shaped seed. This is the
/// priority-3 signal from v0.2 §5.2 ("the same value used as the seed of
/// `.reduce(_:_:)` calls elsewhere in the module — strong signal that the
/// type is already being treated monoidally").
///
/// Veto: non-deterministic body in the operation, identical to the other
/// binary-op templates. If the pattern doesn't hold the template returns
/// `nil`; if the score collapses to `.suppressed`, also `nil`.
public enum IdentityElementTemplate {

    /// Build a suggestion for `pair`, or return `nil` if the score
    /// collapses to `.suppressed`.
    ///
    /// `opsWithIdentitySeed` is the corpus-wide set of operation names
    /// observed at `.reduce(<identity-shape>, op)` call sites — computed
    /// once per discover from `BodySignals.reducerOpsWithIdentitySeed`.
    /// Defaults to the empty set so unit tests for the type-pattern path
    /// don't need to thread it through.
    public static func suggest(
        for pair: IdentityElementPair,
        opsWithIdentitySeed: Set<String> = []
    ) -> Suggestion? {
        var signals: [Signal] = [typeShapeSignal(for: pair)]
        signals.append(identityNamingSignal(for: pair))
        if let emptySeed = emptySeedSignal(for: pair, opsWithIdentitySeed: opsWithIdentitySeed) {
            signals.append(emptySeed)
        }
        if let veto = nonDeterministicVeto(for: pair) {
            signals.append(veto)
        }
        let score = Score(signals: signals)
        guard score.tier != .suppressed else {
            return nil
        }
        return Suggestion(
            templateName: "identity-element",
            evidence: [makeEvidence(operation: pair.operation), makeEvidence(identity: pair.identity)],
            score: score,
            generator: .m1Placeholder,
            explainability: makeExplainability(for: pair, signals: signals),
            identity: makeIdentity(for: pair)
        )
    }

    /// Canonical hash input per PRD §7.5: `template ID | operation
    /// signature | type.identity-name`. The identity is keyed by its
    /// type+name (not its file location) so moving the constant within
    /// the file or across files leaves the suggestion identity stable.
    private static func makeIdentity(for pair: IdentityElementPair) -> SuggestionIdentity {
        let opSig = IdempotenceTemplate.canonicalSignature(of: pair.operation)
        let identityKey: String
        if let containing = pair.identity.containingTypeName {
            identityKey = "\(containing).\(pair.identity.name):\(pair.identity.typeText)"
        } else {
            identityKey = "\(pair.identity.name):\(pair.identity.typeText)"
        }
        return SuggestionIdentity(canonicalInput: "identity-element|\(opSig)|\(identityKey)")
    }

    // MARK: - Signals

    private static func typeShapeSignal(for pair: IdentityElementPair) -> Signal {
        let typeText = pair.identity.typeText
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Type-symmetry signature: (T, T) -> T with identity T.\(pair.identity.name) (T = \(typeText))"
        )
    }

    private static func identityNamingSignal(for pair: IdentityElementPair) -> Signal {
        let identityName = displayedIdentity(for: pair)
        return Signal(
            kind: .exactNameMatch,
            weight: 40,
            detail: "Curated identity-element constant: '\(identityName)' on type \(pair.identity.typeText)"
        )
    }

    private static func emptySeedSignal(
        for pair: IdentityElementPair,
        opsWithIdentitySeed: Set<String>
    ) -> Signal? {
        guard opsWithIdentitySeed.contains(pair.operation.name) else {
            return nil
        }
        return Signal(
            kind: .reduceFoldUsage,
            weight: 20,
            detail: "Accumulator-with-empty-seed: '\(pair.operation.name)' used in .reduce(<identity-shape>, op)"
        )
    }

    private static func nonDeterministicVeto(for pair: IdentityElementPair) -> Signal? {
        guard pair.operation.bodySignals.hasNonDeterministicCall else {
            return nil
        }
        let calls = pair.operation.bodySignals.nonDeterministicAPIsDetected.joined(separator: ", ")
        return Signal(
            kind: .nonDeterministicBody,
            weight: Signal.vetoWeight,
            detail: "Non-deterministic API in body: \(calls)"
        )
    }

    private static func displayedIdentity(for pair: IdentityElementPair) -> String {
        if let containing = pair.identity.containingTypeName {
            return "\(containing).\(pair.identity.name)"
        }
        return pair.identity.name
    }

    // MARK: - Suggestion construction

    private static func makeEvidence(operation summary: FunctionSummary) -> Evidence {
        Evidence(
            displayName: displayName(for: summary),
            signature: signature(for: summary),
            location: summary.location
        )
    }

    private static func makeEvidence(identity candidate: IdentityCandidate) -> Evidence {
        let displayName: String
        if let containing = candidate.containingTypeName {
            displayName = "\(containing).\(candidate.name)"
        } else {
            displayName = candidate.name
        }
        return Evidence(
            displayName: displayName,
            signature: ": \(candidate.typeText)",
            location: candidate.location
        )
    }

    private static func makeExplainability(
        for pair: IdentityElementPair,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let opEvidence = makeEvidence(operation: pair.operation)
        let identityEvidence = makeEvidence(identity: pair.identity)
        whySuggested.append(
            "\(opEvidence.displayName) \(opEvidence.signature) — "
                + "\(opEvidence.location.file):\(opEvidence.location.line)"
        )
        whySuggested.append(
            "\(identityEvidence.displayName)\(identityEvidence.signature) — "
                + "\(identityEvidence.location.file):\(identityEvidence.location.line)"
        )
        for signal in signals {
            whySuggested.append(formatSignalLine(signal))
        }
        let caveats: [String] = [
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer M1 does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it.",
            "The identity property is two-sided: f(t, e) == t AND f(e, t) == t. "
                + "A one-sided identity (e.g. left-identity only) will pass the type pattern but "
                + "fail one of the emitted assertions under M4 sampling."
        ]
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }

    private static func formatSignalLine(_ signal: Signal) -> String {
        if signal.isVeto {
            return "\(signal.detail) (veto)"
        }
        let sign = signal.weight >= 0 ? "+" : ""
        return "\(signal.detail) (\(sign)\(signal.weight))"
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
