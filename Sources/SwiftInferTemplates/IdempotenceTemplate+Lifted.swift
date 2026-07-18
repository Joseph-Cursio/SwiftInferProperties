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

    /// V1.39.C — migrated to the Constraint Engine (PRD §20.2). First
    /// `Constraint<LiftedTransformation>` migration; introduces the
    /// `additionalWhySuggested` Constraint field to thread
    /// `lifted.rationale` between the evidence and signal lines in the
    /// emitted explainability block. Behavior preserved bit-for-bit.
    public static func suggest(
        forLifted lifted: LiftedTransformation,
        vocabulary: Vocabulary = .empty,
        inheritedTypesByName: [String: Set<String>] = [:],
        carrierKindResolver: CarrierKindResolver
    ) -> Suggestion? {
        ConstraintRunner.suggest(
            constraint: makeLiftedConstraint(
                vocabulary: vocabulary,
                inheritedTypesByName: inheritedTypesByName,
                carrierKindResolver: carrierKindResolver
            ),
            subject: lifted
        )
    }

    /// V1.39.C — Constraint factory for the lifted-idempotence variant.
    public static func makeLiftedConstraint(
        vocabulary: Vocabulary,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver
    ) -> Constraint<LiftedTransformation> {
        Constraint<LiftedTransformation>(
            templateName: "idempotence",
            appliesTo: { lifted in
                Self.liftedTypeSymmetrySignal(for: lifted) != nil
            },
            signals: { lifted in
                Self.liftedAccumulatedSignals(
                    for: lifted,
                    vocabulary: vocabulary,
                    inheritedTypesByName: inheritedTypesByName,
                    carrierKindResolver: carrierKindResolver
                )
            },
            evidence: { lifted in [Self.makeLiftedEvidence(lifted)] },
            identity: Self.makeLiftedIdentity(for:),
            carrier: { $0.carrier },
            caveats: { lifted in Self.makeLiftedCaveats(for: lifted) },
            additionalWhySuggested: { [$0.rationale] }
        )
    }

    /// V1.39.C — preserves the pre-migration signal-accumulation order.
    static func liftedAccumulatedSignals(
        for lifted: LiftedTransformation,
        vocabulary: Vocabulary,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver
    ) -> [Signal] {
        guard let typeShape = liftedTypeSymmetrySignal(for: lifted) else {
            return []
        }
        var signals: [Signal] = [typeShape]
        signals.append(contentsOf: liftedAuxiliarySignals(
            for: lifted,
            vocabulary: vocabulary,
            inheritedTypesByName: inheritedTypesByName,
            carrierKindResolver: carrierKindResolver
        ))
        return signals
    }

    /// V1.39.C — caveat list for the lifted variant. The second caveat
    /// embeds the carrier type name.
    static func makeLiftedCaveats(for lifted: LiftedTransformation) -> [String] {
        [
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer V1.19 does not verify protocol conformance — "
                + "confirm before applying.",
            "Property holds iff `\(lifted.carrier)` has value semantics — a "
                + "broken copy-on-write implementation or a class-typed stored "
                + "property would invalidate the lift even though the type "
                + "passed the structural admission gate."
        ]
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
        // Corroborate-only (+15): a mutating method whose docstring documents
        // idempotence — the "already X → no-op" insert/remove contract idiom
        // (`insert … if not already present`). Reaches the mutating carrier the
        // non-lifted path can't; reads the ORIGINAL method's docstring.
        if let docstring = docstringCorroborationSignal(for: lifted.originalSummary) {
            signals.append(docstring)
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
        if let veto = lifted.originalSummary.nonDeterministicVetoSignal {
            signals.append(veto)
        }
        if let coverageVeto = protocolCoverageVeto(
            for: lifted.originalSummary,
            inheritedTypesByName: inheritedTypesByName
        ) {
            signals.append(coverageVeto)
        }
        signals.append(contentsOf: liftedCarrierVetoes(
            for: lifted,
            inheritedTypesByName: inheritedTypesByName
        ))
        return signals
    }

    /// The carrier/name-based lifted vetoes, split out to keep
    /// `liftedAuxiliarySignals` under the cyclomatic-complexity cap.
    private static func liftedCarrierVetoes(
        for lifted: LiftedTransformation,
        inheritedTypesByName: [String: Set<String>]
    ) -> [Signal] {
        var signals: [Signal] = []
        // V1.21.A — IteratorProtocol carrier veto. Cycle-17 finding
        // closure: 4/4 Iterator-shape lifted-idempotence picks reject
        // because Iterator.next()/advance() advance state per call.
        if let iteratorVeto = iteratorProtocolCarrierVeto(
            for: lifted,
            inheritedTypesByName: inheritedTypesByName
        ) {
            signals.append(iteratorVeto)
        }
        // V1.24.B — explicit non-idempotent mutator-name veto. Cycle-20
        // finding closure: 4/4 reject on OC reverse()/removeFirst()/
        // removeLast() lifted-idempotence picks. Generalizes V1.21.A
        // from Iterator-conforming carriers to any value-semantic carrier.
        if let mutatorVeto = mutatorBlocklistVeto(forLifted: lifted) {
            signals.append(mutatorVeto)
        }
        // V1.24.C — non-deterministic mutator-name veto. Cycle-20 finding
        // closure: the OC shuffle() picks surface despite being non-
        // deterministic (existing body-signal detector misses the OC RNG
        // pattern). Name-fallback closes the gap on canonical `shuffle`.
        if let nonDeterministicVeto = nonDeterministicMutatorVeto(forLifted: lifted) {
            signals.append(nonDeterministicVeto)
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
        let summary = lifted.originalSummary
        let labels = summary.parameters
            .map { ($0.label ?? "_") + ":" }
            .joined()
        let displayName = "\(lifted.carrier).\(summary.name)(\(labels))"
        let paramTypes = summary.parameters.map(\.typeText).joined(separator: ", ")
        let signature = "mutating (\(paramTypes)) -> Void  // lifted to (\(lifted.carrier)) -> \(lifted.carrier)"
        // Carry the callee-shape signal so the verify emitter routes the lifted
        // pick to the mutating-instance shape (`var copy = value; copy.method()`)
        // for *any* value-semantic carrier — not just the curated OC set. The lift
        // admission gate (`LiftedTransformation.lift`) already guarantees a
        // mutating instance method, so instance/mutating are always true here;
        // `isNullary` gates out arg-bearing mutators (whose `copy.method()` shape
        // wouldn't compile). Not self-returning — the mutating shape handles it.
        return Evidence(
            displayName: displayName,
            signature: signature,
            location: summary.location,
            isInstanceMethod: summary.containingTypeName != nil && !summary.isStatic,
            isMutatingMethod: summary.isMutating,
            isNullary: summary.parameters.isEmpty,
            returnsSelfType: false
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
