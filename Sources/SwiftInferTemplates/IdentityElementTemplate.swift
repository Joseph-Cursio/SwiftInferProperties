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
    ///
    /// V1.5.2 — `inheritedTypesByName` feeds the protocol-coverage
    /// veto. Op-class-aware on the (identity-constant name, op name)
    /// pair: `.zero` + `+` → `additiveIdentityZero` (covered by
    /// AdditiveArithmetic / Numeric); `.one` + `*` →
    /// `multiplicativeIdentityOne` (covered by Numeric); `.empty` +
    /// `union`/`formUnion`/`+` → `setUnionEmptyIdentity` (covered by
    /// SetAlgebra); `.identity` + any kit-shaped op →
    /// `monoidIdentity` (covered by kit Monoid / CommutativeMonoid /
    /// Group / Semilattice). Other (constant, op) pairs fall through
    /// unsuppressed — closes the cycle-1 cross-product false-positive
    /// (16.7% acceptance) by requiring op-class match before the
    /// veto fires.
    /// V1.40.C — migrated to the Constraint Engine (PRD §20.2). Uses
    /// the **wrapper migration pattern** because the identity-evidence
    /// row's `whySuggested` rendering omits the space between
    /// `displayName` and `signature` (signature is `": Complex"` with
    /// a leading colon that's pre-formatted into the row). The runner's
    /// canonical "displayName signature" join would insert a space and
    /// break bit-for-bit equivalence. The wrapper drives all
    /// Constraint-based work (signals, evidence, identity, carrier) +
    /// rebuilds the Suggestion with the bespoke `makeExplainability`
    /// preserving the no-space rendering.
    public static func suggest(
        for pair: IdentityElementPair,
        opsWithIdentitySeed: Set<String> = [],
        inheritedTypesByName: [String: Set<String>] = [:],
        carrierKindResolver: CarrierKindResolver? = nil
    ) -> Suggestion? {
        let constraint = makeConstraint(
            opsWithIdentitySeed: opsWithIdentitySeed,
            inheritedTypesByName: inheritedTypesByName,
            carrierKindResolver: carrierKindResolver
        )
        guard let runnerSuggestion = ConstraintRunner.suggest(
            constraint: constraint, subject: pair
        ) else {
            return nil
        }
        // Rebuild with bespoke explainability to preserve the no-space
        // identity-evidence rendering.
        return Suggestion(
            templateName: runnerSuggestion.templateName,
            evidence: runnerSuggestion.evidence,
            score: runnerSuggestion.score,
            generator: runnerSuggestion.generator,
            explainability: makeExplainability(
                for: pair,
                signals: runnerSuggestion.score.signals
            ),
            identity: runnerSuggestion.identity,
            carrier: runnerSuggestion.carrier
        )
    }

    /// V1.40.C — Constraint factory. Drives signals + evidence +
    /// identity + carrier; the wrapper `suggest` overrides
    /// explainability rendering.
    public static func makeConstraint(
        opsWithIdentitySeed: Set<String>,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver?
    ) -> Constraint<IdentityElementPair> {
        Constraint<IdentityElementPair>(
            templateName: "identity-element",
            appliesTo: { _ in true },
            signals: { pair in
                Self.accumulatedSignals(
                    for: pair,
                    opsWithIdentitySeed: opsWithIdentitySeed,
                    inheritedTypesByName: inheritedTypesByName,
                    carrierKindResolver: carrierKindResolver
                )
            },
            evidence: { pair in
                [
                    Self.makeEvidence(operation: pair.operation),
                    Self.makeEvidence(identity: pair.identity)
                ]
            },
            identity: Self.makeIdentity(for:),
            // Multi-closure Constraint call: multiple_closures_with_trailing_closure
            // (default) forbids the trailing form trailing_closure would want.
            // swiftlint:disable:next trailing_closure
            carrier: { $0.operation.containingTypeName }
        )
    }

    /// V1.40.C — preserves the pre-migration signal-accumulation order.
    static func accumulatedSignals(
        for pair: IdentityElementPair,
        opsWithIdentitySeed: Set<String>,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver?
    ) -> [Signal] {
        var signals: [Signal] = [typeShapeSignal(for: pair)]
        signals.append(identityNamingSignal(for: pair))
        if let emptySeed = emptySeedSignal(for: pair, opsWithIdentitySeed: opsWithIdentitySeed) {
            signals.append(emptySeed)
        }
        if let carrier = carrierKindResolver?.carrierKindSignal(
            forContainingTypeName: pair.operation.containingTypeName
        ) {
            signals.append(carrier)
        }
        if let veto = nonDeterministicVeto(for: pair) {
            signals.append(veto)
        }
        if let familyVeto = algebraicFamilyMismatchVeto(for: pair) {
            signals.append(familyVeto)
        }
        if let coverageVeto = protocolCoverageVeto(
            for: pair,
            inheritedTypesByName: inheritedTypesByName
        ) {
            signals.append(coverageVeto)
        }
        return signals
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
}

// V1.43 cleanup — signals/vetoes/builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension IdentityElementTemplate {

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

    /// V1.29.B — algebraic-family-mismatch veto. Closes cycle-25 finding 2:
    /// `rescaledDivide(_:_:) × Complex.zero` was a 6-cycle stable reject
    /// because the `+40` curated-identity-constant signal in
    /// `identityNamingSignal` fires unconditionally on type-shape match
    /// without checking that the operator and identity-constant belong to
    /// a compatible algebraic family.
    ///
    /// Fires `Signal.vetoWeight` when:
    ///   - identity name is `zero` and the op name is NOT in
    ///     `IdentityOperatorAlgebra.additiveOperatorNames`, OR
    ///   - identity name is `one` and the op name is NOT in
    ///     `IdentityOperatorAlgebra.multiplicativeOperatorNames`.
    ///
    /// `.empty` and `.identity` constants are unaffected (handled by the
    /// V1.5.2 `identityCoverageCandidate` op-class map). `.none` and
    /// `.default` fall through without veto.
    static func algebraicFamilyMismatchVeto(for pair: IdentityElementPair) -> Signal? {
        let identityName = pair.identity.name
        let opName = pair.operation.name
        guard IdentityOperatorAlgebra.isIncompatibleFamily(
            identityName: identityName, opName: opName
        ) else {
            return nil
        }
        let family = identityName == "zero" ? "additive" : "multiplicative"
        return Signal(
            kind: .protocolCoveredProperty,
            weight: Signal.vetoWeight,
            detail: "Algebraic-family mismatch: identity 'T.\(identityName)' is the "
                + "\(family) identity but operator '\(opName)' is not "
                + "\(family) — type-shape false-positive"
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

    /// V1.5.2 — fires when the candidate (op, identity-constant) pair
    /// matches a curated op-class AND the carrier type's existing
    /// conformances cover that property. Closes cycle-1's
    /// "operator-aware identity-element pairing" gap: the cross-product
    /// of curated identity constants × ops produced 16.7%-acceptance
    /// noise; v1.5 narrows by requiring the (constant, op) pair to map
    /// to a specific KnownProperty before checking conformance coverage.
    private static func protocolCoverageVeto(
        for pair: IdentityElementPair,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        guard let candidate = identityCoverageCandidate(
            identityName: pair.identity.name,
            opName: pair.operation.name
        ) else {
            return nil
        }
        return ProtocolCoverageMap.coverageVetoSignal(
            forTypeText: pair.identity.typeText,
            inheritedTypesByName: inheritedTypesByName,
            candidateProperties: [candidate]
        )
    }

    /// V1.5.2 — (identity-constant name, op name) → KnownProperty
    /// candidate. Returns `nil` for combinations that don't bind to a
    /// kit-published identity law (e.g. `.none` constant or
    /// `.default` constant on arbitrary ops). Internal so tests can
    /// exercise the mapping table directly.
    static func identityCoverageCandidate(
        identityName: String,
        opName: String
    ) -> KnownProperty? {
        switch (identityName, opName) {
        // Additive: .zero + "+" → AdditiveArithmetic / Numeric / SignedNumeric
        case ("zero", "+"):
            return .additiveIdentityZero

        // Multiplicative: .one + "*" → Numeric / SignedNumeric
        case ("one", "*"):
            return .multiplicativeIdentityOne

        // Set-union: .empty + union-shaped ops → SetAlgebra
        case ("empty", "union"), ("empty", "formUnion"), ("empty", "+"):
            return .setUnionEmptyIdentity

        // Kit-monoid: .identity + arbitrary op → Monoid / CommutativeMonoid /
        // Group / Semilattice. The kit's `combine` op is type-bound, not
        // syntactic, so we don't constrain by op name here — any op paired
        // with a `.identity` constant and a `: Monoid`-family conforming
        // type is the kit's intended posture.
        case ("identity", _):
            return .monoidIdentity

        default:
            return nil
        }
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
            displayName: summary.inferenceDisplayName,
            signature: summary.inferenceSignature,
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
            whySuggested.append(signal.formattedLine)
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
}
