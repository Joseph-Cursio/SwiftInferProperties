import SwiftInferCore

// V1.43 cleanup — signals/vetoes/builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension IdentityElementTemplate {

    // MARK: - Signals

    static func typeShapeSignal(for pair: IdentityElementPair) -> Signal {
        let typeText = pair.identity.typeText
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Type-symmetry signature: (T, T) -> T with identity T.\(pair.identity.name) (T = \(typeText))"
        )
    }

    static func identityNamingSignal(for pair: IdentityElementPair) -> Signal {
        let identityName = displayedIdentity(for: pair)
        return Signal(
            kind: .exactNameMatch,
            weight: 40,
            detail: "Curated identity-element constant: '\(identityName)' on type \(pair.identity.typeText)"
        )
    }

    static func emptySeedSignal(
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

    /// V1.5.2 — fires when the candidate (op, identity-constant) pair
    /// matches a curated op-class AND the carrier type's existing
    /// conformances cover that property. Closes cycle-1's
    /// "operator-aware identity-element pairing" gap: the cross-product
    /// of curated identity constants × ops produced 16.7%-acceptance
    /// noise; v1.5 narrows by requiring the (constant, op) pair to map
    /// to a specific KnownProperty before checking conformance coverage.
    static func assumedKitCoverage(
        for pair: IdentityElementPair,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        guard let candidate = identityCoverageCandidate(
            identityName: pair.identity.name,
            opName: pair.operation.name
        ) else {
            return nil
        }
        return ProtocolCoverageMap.assumedCoverageSignal(
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

    static func makeEvidence(operation summary: FunctionSummary) -> Evidence {
        Evidence(
            displayName: summary.inferenceDisplayName,
            signature: summary.inferenceSignature,
            location: summary.location,
            genericParameters: summary.genericParameters
        )
    }

    static func makeEvidence(identity candidate: IdentityCandidate) -> Evidence {
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

    static func makeExplainability(
        for pair: IdentityElementPair,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let opEvidence = makeEvidence(operation: pair.operation)
        let identityEvidence = makeEvidence(identity: pair.identity)
        whySuggested.append(
            "\(opEvidence.displayName) \(opEvidence.signature) — "
                + "\(opEvidence.location)"
        )
        whySuggested.append(
            "\(identityEvidence.displayName)\(identityEvidence.signature) — "
                + "\(identityEvidence.location)"
        )
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        let caveats: [String] = [
            "T must conform to Equatable for the emitted property to compile. "
                + "This tool does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it.",
            "The identity property is two-sided: f(t, e) == t AND f(e, t) == t. "
                + "A one-sided identity (e.g. left-identity only) will pass the type pattern but "
                + "fail one of the emitted assertions under M4 sampling.",
        ]
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }
}
