/// Decides, from a carrier's conformances alone, whether its **iteration order is part of
/// its value** — and further, whether the value is *determined by* its elements.
///
/// This is the structural detection that `OrderSensitiveCarrierNames` explicitly stands in
/// for: that type is a six-name curated denylist whose own doc says it substitutes for
/// "structural order-sensitivity detection pre-SemanticIndex". The two are deliberately left
/// side by side for now — this one is consumed by `SequenceViewModelLawTemplate`, the denylist
/// still by `CommutativityTemplate`'s veto, and migrating that veto is a separate change with
/// its own measurement. Same predicate, opposite polarity: commutativity vetoes *on* an
/// ordered carrier, the model law *requires* one.
///
/// ## Why this exists
///
/// `fixtures/equatable-signal/README.md` measured three real projection bugs — `OrderedSet`
/// order, `BitArray` padding, `Deque` head rotation — that pass **4 of 4** Equatable laws and
/// die at trial ≤3 against the sequence-view model law `a == b ⟺ a.elementsEqual(b)`. That
/// family was recorded as *"deliberately not built"* for one reason: `Set` is a `Sequence`
/// whose iteration order is a function of the hash seed, so the law is **false** for it, and
/// shipping the template without a discriminator would ship a false law.
///
/// ## The rule, and what it was measured against
///
/// Scored against known ground truth over swift-collections, `stdlib/public/core` and
/// swift-foundation — 20 types whose order semantics are documented facts:
///
/// | rule | correct | false positives | safe abstains |
/// |---|---:|---:|---:|
/// | Bidirectional/RandomAccess, veto on `SetAlgebra` | 16 | **1** | 3 |
/// | drop `BidirectionalCollection` | 16 | **0** | 4 |
/// | …and require `ExpressibleByArrayLiteral` | 9 | **0** | 11 |
///
/// Both tightenings were forced by a **witness**, not by an argument:
///
/// **`BidirectionalCollection` is not an order signal.** It says only that you can walk
/// backwards, which a hash-tree's chain supports perfectly well — `TreeSet`, `TreeDictionary`
/// and `BitSet` all conform while their order is representation-determined. `TreeDictionary`
/// was the measured false positive: `BidirectionalCollection`, hash order, and no `SetAlgebra`
/// marker to veto it. The three retained refinements each make *position* value-determined —
/// `MutableCollection` requires overwriting the element at an index, which is meaningless for
/// a hash set and is exactly why `Set` does not conform.
///
/// > **This exclusion is redundant on the corpora measured, and is kept anyway.** Re-adding
/// > `BidirectionalCollection` and re-running all three corpora produces a byte-identical
/// > firing set, because the element-determined gate below already excludes every hash-ordered
/// > type present: `TreeSet` is `SetAlgebra`-vetoed and `TreeDictionary` is
/// > `ExpressibleByDictionaryLiteral`. So the two gates are independent defences that happen to
/// > overlap completely here. Recorded rather than simplified away — the reasoning holds for a
/// > `BidirectionalCollection` hash carrier that *is* array-literal-expressible, which nothing
/// > in these corpora happens to be, and a rule kept for a reason that was measured false would
/// > be worse than one kept for a reason that is merely untested.
///
/// **Ordered is not enough; the value must be DETERMINED BY its elements.** `Range` is a
/// `RandomAccessCollection` whose identity includes bounds that survive emptiness: `5..<5` and
/// `7..<7` have identical element sequences and compare **unequal**, so the biconditional is
/// false. `ExpressibleByArrayLiteral` is the type's own statement that a sequence of elements
/// suffices to construct it — which is precisely what the law claims. It costs `String`,
/// `Data`, `Substring` and `Slice`, all of which become safe abstains.
///
/// Conservative in one direction on purpose: an abstain is a missed law, a false positive is a
/// wrong one, and PRD §3.5 prefers the former.
public enum OrderedCarrierDiscriminator {

    /// Refinements that make a position a value-determined notion rather than an artifact of
    /// the representation.
    ///
    /// Deliberately excludes `BidirectionalCollection` — see the type doc; that inclusion is
    /// what produced the one measured false positive.
    public static let orderSignals: Set<String> = [
        "RandomAccessCollection",
        "MutableCollection",
        "RangeReplaceableCollection"
    ]

    /// The type's own statement that a bare sequence of elements is enough to build it, and
    /// therefore that nothing outside the elements contributes to its identity.
    public static let elementDeterminedSignal = "ExpressibleByArrayLiteral"

    /// An explicit declaration that order is **not** part of the value. `SetAlgebra`'s whole
    /// contract is membership, so a conforming type's `==` must not distinguish orderings.
    public static let orderVetoes: Set<String> = ["SetAlgebra"]

    public enum Verdict: Sendable, Equatable {

        /// Order is part of the value **and** the value is determined by its elements, so
        /// `a == b ⟺ a.elementsEqual(b)` is a claim the type owes. Carries the conformance
        /// that carried the decision, for the explainability block.
        case elementDetermined(orderSignal: String)

        /// Order is explicitly not part of the value — the law is false here.
        case unordered(veto: String)

        /// Not enough evidence either way. Never a reason to emit.
        case abstain(Abstention)
    }

    public enum Abstention: String, Sendable, Equatable {

        /// No `Sequence`/`Collection` conformance recorded — not a sequence carrier at all.
        case notASequence

        /// A sequence, but with no refinement that makes position value-determined.
        /// `Dictionary`, `TreeDictionary`, and anything reached only through
        /// `BidirectionalCollection`.
        case orderNotEstablished

        /// Ordered, but the value carries identity beyond its elements — the `Range` case.
        case notElementDetermined
    }

    /// Whether element **order is part of the carrier's value** — the first half of the
    /// rule, without the element-determined gate.
    ///
    /// **The two consumers need different questions, and conflating them was a live
    /// hazard.** `SequenceViewModelLawTemplate` states a biconditional
    /// (`(a == b) == a.elementsEqual(b)`), so it needs *both* halves: `Range` is
    /// order-sensitive but its value outlives its elements, and the right-to-left
    /// direction is false there. `CommutativityTemplate` asks only whether
    /// `a.union(b)` and `b.union(a)` can differ, which turns on order alone —
    /// `ExpressibleByArrayLiteral` has nothing to say about it.
    ///
    /// Migrating the commutativity veto to the full `verdict` would therefore have
    /// silently dropped `String`, `Substring`, `Data` and `Slice`, every one of them a
    /// carrier where an order-preserving `union` is genuinely non-commutative.
    ///
    /// `false` for an abstention: unresolvable is silence, not a guessed veto.
    public static func isOrderSensitive(forConformances conformances: Set<String>) -> Bool {
        switch verdict(forConformances: conformances) {
        case .elementDetermined:
            return true

        case .unordered:
            return false

        case .abstain(let reason):
            // Ordered, and only the element-determined gate stopped it — which is not a
            // question about order.
            return reason == .notElementDetermined
        }
    }

    /// The verdict for a carrier with these conformance names.
    ///
    /// `conformances` is the corpus-wide inheritance-clause union for the carrier, generic
    /// parameters already stripped — i.e. a value from
    /// `ProtocolCoverageMap.inheritedTypesIndex(from:)`.
    public static func verdict(forConformances conformances: Set<String>) -> Verdict {
        if let veto = orderVetoes.intersection(conformances).min() {
            return .unordered(veto: veto)
        }
        guard let signal = orderSignals.intersection(conformances).min() else {
            let isSequence = conformances.contains("Sequence")
                || conformances.contains("Collection")
                || conformances.contains("BidirectionalCollection")
            return .abstain(isSequence ? .orderNotEstablished : .notASequence)
        }
        guard conformances.contains(elementDeterminedSignal) else {
            return .abstain(.notElementDetermined)
        }
        return .elementDetermined(orderSignal: signal)
    }
}
