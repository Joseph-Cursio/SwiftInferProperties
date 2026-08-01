import SwiftInferCore
import Testing

/// The **ordered-carrier discriminator** — is a carrier's iteration order part of its value,
/// and is its value determined by its elements?
///
/// `fixtures/equatable-signal/README.md` recorded the sequence-view model law as deliberately
/// not built, for one reason: *"`Set` is a `Sequence` whose iteration order is unspecified, so
/// it fails the law spuriously. Resolving that needs an ordered-carrier discriminator, which
/// is its own measurement."* These are that measurement, pinned.
///
/// Every arm below is a real type with documented order semantics, and the two rows that
/// forced the rule into its current shape — `TreeDictionary` and `Range` — each get their own
/// test with the reason attached.
@Suite("Ordered-carrier discriminator — measured against known order semantics")
struct OrderedCarrierDiscriminatorTests {

    /// The three real projection bugs `fixtures/equatable-signal` measured, with the
    /// conformances each type actually declares.
    static let bugWitnessConformances: [(String, Set<String>)] = [
        ("OrderedSet", ["RandomAccessCollection", "ExpressibleByArrayLiteral", "Equatable"]),
        ("Deque", ["MutableCollection", "RandomAccessCollection", "ExpressibleByArrayLiteral"]),
        ("BitArray", ["MutableCollection", "RandomAccessCollection", "ExpressibleByArrayLiteral"])
    ]

    /// Three unordered carriers, each of which would take a false law without the veto.
    static let setAlgebraConformances: [(String, Set<String>)] = [
        ("Set", ["Collection", "Sequence", "SetAlgebra", "ExpressibleByArrayLiteral"]),
        ("BitSet", ["BidirectionalCollection", "SetAlgebra", "ExpressibleByArrayLiteral"]),
        ("TreeSet", ["BidirectionalCollection", "SetAlgebra", "ExpressibleByArrayLiteral"])
    ]

    // MARK: - The three bug witnesses must survive

    /// These are the whole point. `fixtures/equatable-signal` measured all three passing 4/4
    /// Equatable laws with a real projection bug and dying against the model law at trial ≤3.
    /// A discriminator that excluded any of them would be correct and useless.
    @Test(
        "The three projection-bug witnesses are element-determined",
        arguments: Self.bugWitnessConformances
    )
    func bugWitnessesSurvive(name: String, conformances: Set<String>) {
        let verdict = OrderedCarrierDiscriminator.verdict(forConformances: conformances)
        guard case .elementDetermined = verdict else {
            Issue.record("\(name) must be element-determined, got \(verdict)")
            return
        }
    }

    // MARK: - The unordered carriers must be refused

    /// `SetAlgebra`'s contract is membership, so a conforming type's `==` must not distinguish
    /// orderings. This is the cheap half of the discriminator and it catches `Set`, `BitSet`
    /// and `TreeSet` outright.
    @Test(
        "SetAlgebra vetoes, even when the type is otherwise ordered-looking",
        arguments: Self.setAlgebraConformances
    )
    func setAlgebraVetoes(name: String, conformances: Set<String>) {
        let verdict = OrderedCarrierDiscriminator.verdict(forConformances: conformances)
        #expect(verdict == .unordered(veto: "SetAlgebra"), "\(name) must be vetoed")
    }

    /// **The witness that removed `BidirectionalCollection` from the order signals.**
    ///
    /// `TreeDictionary` was the single measured false positive of the first rule: it is a
    /// `BidirectionalCollection` with hash-determined iteration order, and being a dictionary
    /// rather than a set it has no `SetAlgebra` conformance to veto it. Walking backwards is
    /// something a hash-tree's chain supports perfectly well, so `BidirectionalCollection`
    /// says nothing about whether order is part of the value.
    @Test("TreeDictionary abstains — Bidirectional is not an order signal")
    func treeDictionaryAbstains() {
        let verdict = OrderedCarrierDiscriminator.verdict(forConformances: [
            "BidirectionalCollection", "Collection", "Sequence",
            "ExpressibleByDictionaryLiteral", "Equatable", "Hashable"
        ])
        #expect(verdict == .abstain(.orderNotEstablished))
    }

    /// Dictionary reaches only `Collection`, so it abstains one step earlier.
    @Test("Dictionary abstains")
    func dictionaryAbstains() {
        let verdict = OrderedCarrierDiscriminator.verdict(forConformances: [
            "Collection", "Sequence", "ExpressibleByDictionaryLiteral", "Equatable"
        ])
        #expect(verdict == .abstain(.orderNotEstablished))
    }

    // MARK: - Ordered is not enough

    /// **The witness that added the `ExpressibleByArrayLiteral` requirement.**
    ///
    /// `Range` is a `RandomAccessCollection` whose identity includes bounds that survive
    /// emptiness. `5..<5` and `7..<7` have identical (empty) element sequences and compare
    /// **unequal**, so `a.elementsEqual(b) ⟹ a == b` is false — and that direction is the one
    /// catching two of the three bug witnesses, so it cannot simply be dropped. The type must
    /// be determined by its elements, not merely ordered.
    @Test("Range abstains — ordered, but its value outlives its elements")
    func rangeAbstains() {
        let verdict = OrderedCarrierDiscriminator.verdict(forConformances: [
            "RandomAccessCollection", "BidirectionalCollection", "Collection",
            "Equatable", "Hashable", "Sendable"
        ])
        #expect(verdict == .abstain(.notElementDetermined))
    }

    /// `String` is genuinely ordered and genuinely element-determined in spirit, but is not
    /// `ExpressibleByArrayLiteral`. Abstaining here is the conservative direction and it is
    /// also the right answer for a subtler reason: `String.==` is Unicode canonical
    /// equivalence, which is not a claim about `Character` positions.
    @Test("String abstains rather than guessing")
    func stringAbstains() {
        let verdict = OrderedCarrierDiscriminator.verdict(forConformances: [
            "BidirectionalCollection", "RangeReplaceableCollection", "Comparable",
            "ExpressibleByStringLiteral", "Equatable", "Hashable"
        ])
        #expect(verdict == .abstain(.notElementDetermined))
    }

    @Test("A non-sequence carrier is distinguished from an unordered one")
    func nonSequenceAbstains() {
        let verdict = OrderedCarrierDiscriminator.verdict(forConformances: [
            "Equatable", "Hashable", "CustomStringConvertible"
        ])
        #expect(verdict == .abstain(.notASequence))
    }

    // MARK: - Ordering of the rule itself

    /// The veto must be checked BEFORE the positive signals, or an
    /// `ExpressibleByArrayLiteral` `SetAlgebra` type — which is to say `Set` itself, and
    /// `BitSet`, and `TreeSet` — would be admitted on the strength of a conformance that says
    /// nothing about order.
    @Test("The SetAlgebra veto outranks a positive order signal")
    func vetoOutranksSignal() {
        let verdict = OrderedCarrierDiscriminator.verdict(forConformances: [
            "SetAlgebra", "RandomAccessCollection", "MutableCollection",
            "ExpressibleByArrayLiteral"
        ])
        #expect(verdict == .unordered(veto: "SetAlgebra"))
    }

    /// The reported signal is stable regardless of `Set` iteration order, so rendered output
    /// is byte-stable across runs (PRD §16 #6).
    @Test("The reported order signal is deterministic")
    func reportedSignalIsDeterministic() {
        let conformances: Set<String> = [
            "RandomAccessCollection", "MutableCollection", "RangeReplaceableCollection",
            "ExpressibleByArrayLiteral"
        ]
        let verdicts = (0..<8).map { _ in
            OrderedCarrierDiscriminator.verdict(forConformances: conformances)
        }
        #expect(Set(verdicts.map { "\($0)" }).count == 1)
        #expect(verdicts.first == .elementDetermined(orderSignal: "MutableCollection"))
    }
}
