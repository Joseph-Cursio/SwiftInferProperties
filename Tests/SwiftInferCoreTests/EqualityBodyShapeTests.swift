import SwiftInferCore
import Testing

/// `EqualityBodyClassifier` — what a hand-written `==` actually does.
///
/// `fixtures/equatable-signal/README.md`'s measured conclusion is that an `Equatable`
/// conformance does not predict refutability and the **body shape** does. Every arm
/// below is a real `==` body from swift-collections or the standard library, with the
/// file and line it came from, because the two extensions to this classifier were both
/// forced by real bodies rather than designed up front.
@Suite("Equality body shape — classified from the bodies that defined the cases")
struct EqualityBodyShapeTests {

    private func shape(_ body: String) -> EqualityBodyShape {
        let source = """
        struct Carrier {
            static func == (left: Carrier, right: Carrier) -> Bool \(body)
        }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Carrier.swift")
        guard let equals = summaries.first(where: { $0.name == "==" }) else { return .unclassified }
        return equals.bodySignals.equalityBodyShape ?? .unclassified
    }

    // MARK: - The vacuity cases

    /// `Deque+Equatable.swift:21` — count guard, referential fast path, then
    /// `elementsEqual`. A law about the sequence view restates the result expression.
    @Test("Deque's body — an explicit elementsEqual")
    func dequeShape() {
        let result = shape("""
        {
            let lhsCount = left.count
            if lhsCount != right.count { return false }
            if lhsCount == 0 || left._storage.isIdentical(to: right._storage) { return true }
            return left.elementsEqual(right)
        }
        """)
        #expect(result == .sequenceComparison(callee: "elementsEqual"))
    }

    /// `Array.swift:2007` — the same comparison inlined over indices.
    ///
    /// This case exists because the first classifier keyed on `elementsEqual` alone and
    /// reported `Array` as `.unclassified`, which would have left three of the seven
    /// carriers the signal exists to score at full tier for a vacuous law.
    @Test("Array's body — elementsEqual inlined as an indexed loop")
    func arrayShape() {
        let result = shape("""
        {
            let lhsCount = left.count
            if lhsCount != right.count { return false }
            if lhsCount == 0 { return true }
            for idx in 0..<lhsCount {
                if left[idx] != right[idx] { return false }
            }
            return true
        }
        """)
        #expect(result == .sequenceComparison(callee: "inlined element loop"))
    }

    /// `ArraySlice.swift:1466` — the third spelling, two parallel iterators.
    @Test("ArraySlice's body — elementsEqual inlined as parallel iterators")
    func arraySliceShape() {
        let result = shape("""
        {
            let lhsCount = left.count
            if lhsCount != right.count { return false }
            var streamLHS = left.makeIterator()
            var streamRHS = right.makeIterator()
            var nextLHS = streamLHS.next()
            while nextLHS != nil {
                let nextRHS = streamRHS.next()
                if nextLHS != nextRHS { return false }
                nextLHS = streamLHS.next()
            }
            return true
        }
        """)
        #expect(result == .sequenceComparison(callee: "inlined pairwise scan"))
    }

    // MARK: - The refutable case

    /// `BitArray+Equatable.swift:27`. The guard's field counts: equality genuinely
    /// depends on `_count` as well as `_storage`, and reporting only the latter would
    /// misdescribe what equality means for the type.
    @Test("BitArray's body — a projection, with the guard's field included")
    func bitArrayShape() {
        let result = shape("""
        {
            guard left._count == right._count else { return false }
            return left._storage == right._storage
        }
        """)
        #expect(result == .storedFieldProjection(members: ["_count", "_storage"]))
    }

    /// `OrderedSet+Equatable.swift:27` — a projection onto a single field, under
    /// Swift's implicit return.
    @Test("OrderedSet's body — a single-field projection with an implicit return")
    func orderedSetShape() {
        #expect(shape("{ left._elements == right._elements }")
            == .storedFieldProjection(members: ["_elements"]))
    }

    // MARK: - The conversion case

    /// The fixture's `UnorderedMutantSet` shape: everything the conversion discards is
    /// information `==` has stopped distinguishing.
    @Test("A conversion comparison is distinguished from a projection")
    func conversionShape() {
        #expect(shape("{ Set(left.elements) == Set(right.elements) }")
            == .conversionComparison(via: "Set"))
    }

    /// `Array(a) == Array(b)` preserves the element sequence, so it is the sequence
    /// comparison rather than a lossy conversion.
    @Test("A sequence-preserving conversion is the sequence comparison, not a conversion")
    func sequencePreservingConversion() {
        #expect(shape("{ Array(left) == Array(right) }")
            == .sequenceComparison(callee: "Array"))
    }

    // MARK: - The false positive that tightened the rule

    /// **`OrderSet.UnorderedView+Equatable.swift:105`, and it was a real false
    /// positive of the looser rule.**
    ///
    /// Result `true`, a loop containing `return false`, both operands referenced — it
    /// satisfied every condition the first pairwise-scan rule checked, while meaning
    /// the exact reverse: it iterates ONE operand and SEARCHES the other, which is a
    /// deliberately order-*insensitive* comparison.
    ///
    /// A pairwise scan walks both operands in lockstep. A membership scan does not.
    @Test("A membership scan is NOT a sequence comparison")
    func membershipScanIsNotASequenceComparison() {
        let result = shape("""
        {
            if left._base.storage === right._base.storage { return true }
            guard left._base.count == right._base.count else { return false }
            for item in left._base {
                if !right._base.contains(item) { return false }
            }
            return true
        }
        """)
        #expect(result != .sequenceComparison(callee: "inlined element loop"))
        #expect(result != .sequenceComparison(callee: "inlined pairwise scan"))
    }

    /// An ordering comparison is not an equality projection — the fixture's
    /// `OrderedLeakPair` is a `<=` slipping in where `==` was meant, and it must not be
    /// reported as a field projection.
    @Test("An ordering comparison is not reported as a projection")
    func orderingIsNotAProjection() {
        #expect(shape("{ left.value <= right.value }") == .unclassified)
    }

    // MARK: - Scope

    /// The classification is computed only for `==`, so the walk is paid once per
    /// Equatable conformance rather than once per function in the corpus.
    @Test("Only `==` is classified")
    func onlyEqualsIsClassified() {
        let source = """
        struct Carrier {
            static func isSame(left: Carrier, right: Carrier) -> Bool {
                left.value == right.value
            }
        }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Carrier.swift")
        #expect(summaries.first { $0.name == "isSame" }?.bodySignals.equalityBodyShape == nil)
    }

    /// A protocol requirement has no body to read.
    @Test("A bodyless declaration classifies as nil, not as a shape")
    func bodylessDeclaration() {
        let summaries = FunctionScanner.scan(
            source: "protocol Carrier { static func == (left: Self, right: Self) -> Bool }",
            file: "Carrier.swift"
        )
        #expect(summaries.first { $0.name == "==" }?.bodySignals.equalityBodyShape == nil)
    }
}
