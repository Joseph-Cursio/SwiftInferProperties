import SwiftInferCore

// V1.43 cleanup — signals/vetoes/builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension CommutativityTemplate {

    // MARK: - Signals

    /// B29 — veto for a set-combination commutativity suggestion on an
    /// order-sensitive carrier. `union` / `intersection` are commutative as a
    /// *set* semilattice, but `OrderedSet` / `Array` / … compare element order
    /// in `==`, so `a.union(b) == b.union(a)` is false there (it holds only
    /// under an order-insensitive comparison such as `isEqualSet`).
    ///
    /// **Structural first, denylist second.** `OrderedCarrierDiscriminator` answers
    /// "is order part of this carrier's value?" from its conformances, so the veto now
    /// fires on *any* order-sensitive carrier rather than on six hardcoded names — a
    /// user's own `RandomAccessCollection` with an order-preserving `union` is caught
    /// where it previously was not. That is what `OrderSensitiveCarrierNames`' own doc
    /// said it was standing in for: "structural order-sensitivity detection
    /// pre-SemanticIndex".
    ///
    /// It reads `isOrderSensitive` rather than the full `verdict`, because the two
    /// consumers ask different questions — see that method. Using the full verdict here
    /// would drop `String` / `Substring` / `Data` / `Slice`, all of them carriers where
    /// an order-preserving `union` is genuinely non-commutative.
    ///
    /// **The denylist is kept as a union, not replaced.** Measured across
    /// swift-collections, `stdlib/public/core`, swift-foundation, swift-syntax and
    /// swift-nio, the two rules agree on **every** carrier that declares one of these
    /// verbs — zero disagreements. But the agreement is thinner than it looks: five of
    /// the six denylist names never appear at all, because `Array` / `Deque` /
    /// `OrderedDictionary` declare no set operations, so `OrderedSet` is the only entry
    /// the denylist actively fires on. The residue that keeps the denylist alive is
    /// `OrderedDictionary`, which conforms to `Sequence` and nothing that marks position
    /// as value-determined, so the structural rule abstains on it. Dropping the denylist
    /// would be safe on everything measured and unsafe on a shape nobody has written yet.
    ///
    /// Associativity and idempotence are NOT vetoed: both hold on these carriers
    /// (order-preserving append is associative; `x ∪ x == x`).
    static func orderSensitiveCarrierVetoSignal(
        for summary: FunctionSummary,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        guard setCombinationVerbs.contains(summary.name),
              let carrier = summary.containingTypeName else {
            return nil
        }
        let stripped = OrderSensitiveCarrierNames.strippingGenericParameters(carrier)
        let structural = OrderedCarrierDiscriminator.isOrderSensitive(
            forConformances: inheritedTypesByName[stripped] ?? []
        )
        let listed = OrderSensitiveCarrierNames.contains(carrier)
        guard structural || listed else { return nil }
        let basis = structural
            ? "its conformances make position value-determined"
            : "it is on the curated order-sensitive carrier list"
        return Signal(
            kind: .orderSensitiveCarrier,
            weight: Signal.vetoWeight,
            detail: "Order-sensitive carrier: \(stripped).== compares element order — "
                + "\(basis) — so '\(summary.name)' is NOT commutative under it. "
                + "a.\(summary.name)(b) and b.\(summary.name)(a) hold the same members in a "
                + "different order. The semilattice commutativity law holds only under an "
                + "order-insensitive comparison such as isEqualSet"
        )
    }

    /// B24 — counter-signal that suppresses a shape-only commutativity candidate.
    /// The caller invokes it only when neither a commutative name nor an
    /// anti-commutativity name matched, so the bare `(T, T) -> T` shape is all
    /// there is — and a correct `backoffDelay` / `weighted` matches that shape
    /// without being commutative. `-20` drops Score 30 → 10, below the Possible
    /// floor; a named commutative op keeps this from firing.
    static func unsupportedShapeCounterSignal(
        for summary: FunctionSummary
    ) -> Signal? {
        Signal(
            kind: .unsupportedAlgebraicShape,
            weight: -20,
            detail: "'\(summary.name)' matched only the (T, T) -> T shape — no commutative "
                + "name; commutativity is not entailed by the shape alone"
        )
    }

    /// V1.5.2 — fires when the candidate type's existing protocol
    /// conformances cover the commutativity property the template
    /// would emit, mapped op-class-aware: `+` → additive, `*` →
    /// multiplicative, `union`/`formUnion` → set-union. Other ops
    /// don't bind to a kit-published commutativity law (e.g. a
    /// user-named `combine` on Int isn't covered by Numeric's `+`/`*`
    /// commutativity laws), so they fall through unsuppressed.
    static func assumedKitCoverage(
        for summary: FunctionSummary,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        let candidates = commutativityCoverageCandidates(forOp: summary.name)
        guard !candidates.isEmpty else { return nil }
        return ProtocolCoverageMap.assumedCoverageSignal(
            forTypeText: summary.parameters.first?.typeText,
            inheritedTypesByName: inheritedTypesByName,
            candidateProperties: candidates
        )
    }

    // MARK: - Suggestion construction

    static func makeExplainability(
        for summary: FunctionSummary,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let evidence = summary.inferenceEvidence
        whySuggested.append(
            "\(evidence.displayName) \(evidence.signature) — \(evidence.location)"
        )
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        var caveats: [String] = [
            "T must conform to Equatable for the emitted property to compile. "
                + "This tool does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it.",
        ]
        if let fpCaveat = floatingPointAdvisory(for: summary) {
            caveats.append(fpCaveat)
        }
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }
}
