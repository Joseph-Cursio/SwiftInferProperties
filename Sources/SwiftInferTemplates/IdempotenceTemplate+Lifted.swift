import SwiftInferCore

/// V1.19.B — `IdempotenceTemplate` lift admission. Re-admits the
/// `mutating func` surface to idempotence scoring via
/// `LiftedTransformation` (defined in `SwiftInferCore`). Two shapes
/// admit per the v1.19 plan §2 deliverable 2a:
///
/// | Original mutating shape | Lifted shape | Idempotence test |
/// |---|---|---|
/// | `mutating func op() -> Void` | `(T) -> T` | `op'(op'(s)) == op'(s)` |
/// | `mutating func op(x: T) -> Void` (param == carrier) | `(T, T) -> T` | x-curried `op'(op'(s, x), x) == op'(s, x)` |
///
/// Examples: `Set.removeAll` (no-param) ⇒ unary lift; `Set.formUnion(_:Self)`
/// (param matches carrier) ⇒ binary x-curried lift — the canonical
/// SetAlgebra idempotent-union law.
///
/// The single-parameter case where `x: X` does NOT match the carrier
/// (`mutating func increment(by: Int)` on `struct Counter`) is **not**
/// an idempotence candidate — `op'(op'(s, x), x) == op'(s, x)` doesn't
/// hold for `increment` (it doubles). Those candidates flow through
/// `IdentityElementPairing` (`incremented(c, by: 0) == c`) and
/// `CompositionTemplate` (`incremented(incremented(c, a), b) ==
/// incremented(c, a + b)`), both V1.19.C.
extension IdempotenceTemplate {

    /// Build a suggestion for `lifted`, or return `nil` when the lifted
    /// shape isn't an idempotence candidate or the score collapses.
    public static func suggest(
        forLifted lifted: LiftedTransformation,
        vocabulary: Vocabulary = .empty,
        inheritedTypesByName: [String: Set<String>] = [:],
        carrierKindResolver: CarrierKindResolver
    ) -> Suggestion? {
        guard let typeShape = liftedTypeSymmetrySignal(for: lifted) else {
            return nil
        }
        var signals: [Signal] = [typeShape]
        signals.append(contentsOf: liftedAuxiliarySignals(
            for: lifted,
            vocabulary: vocabulary,
            inheritedTypesByName: inheritedTypesByName,
            carrierKindResolver: carrierKindResolver
        ))
        let score = Score(signals: signals)
        guard score.tier != .suppressed else {
            return nil
        }
        return Suggestion(
            templateName: "idempotence",
            evidence: [makeLiftedEvidence(lifted)],
            score: score,
            generator: .m1Placeholder,
            explainability: makeLiftedExplainability(for: lifted, signals: signals),
            identity: makeLiftedIdentity(for: lifted)
        )
    }

    // MARK: - Type-shape

    /// Returns the type-symmetry signal for the two admissible lifted
    /// shapes; `nil` for any other shape (the lift is not an idempotence
    /// candidate).
    private static func liftedTypeSymmetrySignal(
        for lifted: LiftedTransformation
    ) -> Signal? {
        let originalParams = lifted.originalSummary.parameters
        // Disqualify if any original parameter is `inout` — `var` aliasing
        // through inout breaks the lift's value-semantic guarantee.
        guard !originalParams.contains(where: \.isInout) else { return nil }
        if originalParams.isEmpty {
            return Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Type-symmetry signature: (\(lifted.carrier)) -> "
                    + "\(lifted.carrier) (lifted from no-param mutating method)"
            )
        }
        if originalParams.count == 1,
           originalParams[0].typeText == lifted.carrier {
            return Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Type-symmetry signature: (\(lifted.carrier), "
                    + "\(lifted.carrier)) -> \(lifted.carrier) (lifted, "
                    + "x-curried idempotence on param matching carrier)"
            )
        }
        return nil
    }

    /// Bundles the optional name / counter / veto / coverage signals into
    /// a single helper so the public `suggest(forLifted:)` stays under
    /// SwiftLint's cyclomatic-complexity ceiling. Mirrors the V1.18.A
    /// `InversePairTemplate.counterAndCoverageSignals` split.
    private static func liftedAuxiliarySignals(
        for lifted: LiftedTransformation,
        vocabulary: Vocabulary,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver
    ) -> [Signal] {
        var signals: [Signal] = []
        // Curated naming on the original method name. Reuses
        // `nameSignal(for:vocabulary:)` from the non-lifted path so a
        // mutating method called `normalize` matches the curated verb
        // list identically.
        if let name = nameSignal(for: lifted.originalSummary, vocabulary: vocabulary) {
            signals.append(name)
        }
        // Direction-label / domain-marker counters carry over from the
        // non-lifted scoring stack (apply to original parameter labels).
        if let direction = directionLabelCounterSignal(for: lifted.originalSummary) {
            signals.append(direction)
        }
        if let domainMarker = domainMarkerCounterSignal(for: lifted.originalSummary) {
            signals.append(domainMarker)
        }
        // SetAlgebra-shape veto applies to the original signature; a
        // `mutating func formUnion(_ other: Self)` would otherwise
        // double-up with the v1.18.C dual-style consistency template
        // (and the kit's SetAlgebra coverage). The veto suppresses the
        // lifted idempotence claim when the kit law already covers it.
        if let setAlgebra = setAlgebraShapeVeto(for: lifted.originalSummary) {
            signals.append(setAlgebra)
        }
        // Carrier signal — always +5 by admission gate (.valueSemantic).
        if let carrier = carrierKindResolver.carrierKindSignal(
            forContainingTypeName: lifted.carrier
        ) {
            signals.append(carrier)
        }
        // Lifted-from-mutation badge (+10) — V1.19.A signal kind.
        signals.append(liftedFromMutationSignal(for: lifted))
        if let veto = nonDeterministicVeto(for: lifted.originalSummary) {
            signals.append(veto)
        }
        if let coverageVeto = protocolCoverageVeto(
            for: lifted.originalSummary,
            inheritedTypesByName: inheritedTypesByName
        ) {
            signals.append(coverageVeto)
        }
        // V1.21.A — IteratorProtocol carrier veto. Cycle-17 finding
        // closure: 4/4 Iterator-shape lifted-idempotence picks reject
        // because Iterator.next()/advance() advance state per call.
        if let iteratorVeto = iteratorProtocolCarrierVeto(
            for: lifted,
            inheritedTypesByName: inheritedTypesByName
        ) {
            signals.append(iteratorVeto)
        }
        return signals
    }

    private static func liftedFromMutationSignal(
        for lifted: LiftedTransformation
    ) -> Signal {
        let labels = lifted.originalSummary.parameters
            .map { ($0.label ?? "_") + ":" }
            .joined()
        return Signal(
            kind: .liftedFromMutation,
            weight: 10,
            detail: "Lifted from `mutating func \(lifted.carrier).\(lifted.originalSummary.name)(\(labels))`"
        )
    }

    // MARK: - Identity

    /// Identity hash includes a `lifted-` prefix so the suggestion is
    /// disjoint from any non-lifted idempotence candidate that happened
    /// to share the same canonical signature (impossible by construction
    /// since the non-lifted path gates on `!isMutating` and the original
    /// summary's return type is `Void`, but the prefix makes intent
    /// explicit and keeps the skip-marker hash space disjoint).
    private static func makeLiftedIdentity(for lifted: LiftedTransformation) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: "idempotence-lifted|" + canonicalSignature(of: lifted.originalSummary)
        )
    }

    // MARK: - Evidence + explainability

    private static func makeLiftedEvidence(_ lifted: LiftedTransformation) -> Evidence {
        let labels = lifted.originalSummary.parameters
            .map { ($0.label ?? "_") + ":" }
            .joined()
        let displayName = "\(lifted.carrier).\(lifted.originalSummary.name)(\(labels))"
        let paramTypes = lifted.originalSummary.parameters.map(\.typeText).joined(separator: ", ")
        let signature = "mutating (\(paramTypes)) -> Void  // lifted to (\(lifted.carrier)) -> \(lifted.carrier)"
        return Evidence(
            displayName: displayName,
            signature: signature,
            location: lifted.originalSummary.location
        )
    }

    private static func makeLiftedExplainability(
        for lifted: LiftedTransformation,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let evidence = makeLiftedEvidence(lifted)
        whySuggested.append(
            "\(evidence.displayName) \(evidence.signature) — "
                + "\(evidence.location.file):\(evidence.location.line)"
        )
        whySuggested.append(lifted.rationale)
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        let caveats: [String] = [
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer V1.19 does not verify protocol conformance — "
                + "confirm before applying.",
            "Property holds iff `\(lifted.carrier)` has value semantics — a "
                + "broken copy-on-write implementation or a class-typed stored "
                + "property would invalidate the lift even though the type "
                + "passed the structural admission gate."
        ]
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }
}
