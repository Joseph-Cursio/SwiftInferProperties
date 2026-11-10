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
                    Self.makeEvidence(identity: pair.identity),
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
        if let veto = pair.operation.nonDeterministicVetoSignal {
            signals.append(veto)
        }
        if let familyVeto = algebraicFamilyMismatchVeto(for: pair) {
            signals.append(familyVeto)
        }
        if let assumedCoverage = assumedKitCoverage(
            for: pair,
            inheritedTypesByName: inheritedTypesByName
        ) {
            signals.append(assumedCoverage)
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
