import Foundation

/// swift-collections (`apple/swift-collections`) laws. Each type inherits the
/// standard-library shapes from Appendix A via protocol refinement, plus a
/// family-specific law the inherited rows don't reach (Deque's double-ended
/// symmetry, OrderedSet's order-preserving union, Heap's model-based drain).
///
/// All carry the module they need in `imports`, so `--verify` builds them
/// against the real swift-collections release. Non-negative masking (`& 63`) is
/// used where a type needs non-negative elements (`BitSet`).
extension StandardLibraryProperties {

    // MARK: - Deque (DequeModule)

    private static let dequeLaws: [KnownProperty] = [
        law(
            "Deque", "reverse is an involution", "Array(d.reversed().reversed()) == Array(d)",
            "let d = Deque(randArr()); return Array(d.reversed().reversed()) == Array(d)",
            template: "involution", imports: ["DequeModule"]
        ),
        law(
            "Deque", "count is additive over concatenation", "(a + b).count == a.count + b.count",
            "let a = Deque(randArr()), b = Deque(randArr()); return (a + b).count == a.count + b.count",
            imports: ["DequeModule"]
        ),
        law(
            "Deque", "prepend/removeFirst round-trip (double-ended symmetry)",
            "prepend(x) then removeFirst() yields x and restores the deque",
            "let arr = randArr(); var d = Deque(arr); let x = randInt(); d.prepend(x); "
                + "let head = d.removeFirst(); return head == x && Array(d) == arr",
            imports: ["DequeModule"]
        )
    ]

    // MARK: - OrderedSet / OrderedDictionary (OrderedCollections)

    private static let orderedLaws: [KnownProperty] = [
        law(
            "OrderedSet", "idempotent under union", "x.union(x) == x",
            "let x = OrderedSet(randArr()); return x.union(x) == x",
            imports: ["OrderedCollections"]
        ),
        law(
            "OrderedSet", "commutative under membership (NOT under order)",
            "Set(x.union(y)) == Set(y.union(x))",
            "let x = OrderedSet(randArr()), y = OrderedSet(randArr()); "
                + "return Set(x.union(y)) == Set(y.union(x))",
            note: "OrderedSet.union keeps the LEFT operand's order, so it is NOT order-commutative "
                + "(the finer equality) — only membership-commutative (the coarser one).",
            imports: ["OrderedCollections"]
        ),
        law(
            "OrderedSet", "union preserves left order", "union's prefix is x, in x's order",
            "let x = OrderedSet(randArr()), y = OrderedSet(randArr()); "
                + "return Array(x.union(y).prefix(x.count)) == Array(x)",
            note: "A total, deterministic law: x.union(y) is x's elements in x's order, then y's novel ones.",
            imports: ["OrderedCollections"]
        ),
        law(
            "OrderedDictionary", "mapValues functor identity", "d.mapValues { $0 } == d",
            "var d = OrderedDictionary<Int, Int>(); for (key, value) in randDict() { d[key] = value }; "
                + "return d.mapValues { $0 } == d",
            imports: ["OrderedCollections"]
        )
    ]

    // MARK: - BitSet (BitCollections) — full SetAlgebra

    private static let bitSetLaws: [KnownProperty] = [
        law(
            "BitSet", "commutative under union", "a.union(b) == b.union(a)",
            "let a = BitSet(randArr().map { $0 & 63 }), b = BitSet(randArr().map { $0 & 63 }); "
                + "return a.union(b) == b.union(a)",
            witnesses: "Semilattice", template: "commutativity", imports: ["BitCollections"]
        ),
        law(
            "BitSet", "commutative under intersection", "a.intersection(b) == b.intersection(a)",
            "let a = BitSet(randArr().map { $0 & 63 }), b = BitSet(randArr().map { $0 & 63 }); "
                + "return a.intersection(b) == b.intersection(a)",
            witnesses: "Semilattice", imports: ["BitCollections"]
        ),
        law(
            "BitSet", "idempotent under union", "a.union(a) == a",
            "let a = BitSet(randArr().map { $0 & 63 }); return a.union(a) == a",
            witnesses: "Semilattice", imports: ["BitCollections"]
        ),
        law(
            "BitSet", "absorption", "a.union(a.intersection(b)) == a",
            "let a = BitSet(randArr().map { $0 & 63 }), b = BitSet(randArr().map { $0 & 63 }); "
                + "return a.union(a.intersection(b)) == a",
            witnesses: "SetAlgebra", imports: ["BitCollections"]
        )
    ]

    // MARK: - TreeSet / TreeDictionary (HashTreeCollections) — persistent CHAMP

    private static let treeLaws: [KnownProperty] = [
        law(
            "TreeSet", "commutative under union", "a.union(b) == b.union(a)",
            "let a = TreeSet(randArr()), b = TreeSet(randArr()); return a.union(b) == b.union(a)",
            witnesses: "Semilattice", template: "commutativity", imports: ["HashTreeCollections"]
        ),
        law(
            "TreeSet", "value semantics — mutating a copy leaves the original untouched",
            "inserting into a copy does not affect the original",
            "let original = TreeSet(randArr()); var copy = original; let fresh = 100_000 + abs(randInt()); "
                + "copy.insert(fresh); return !original.contains(fresh) && copy.contains(fresh)",
            note: "For persistent CHAMP structures, value semantics IS the product promise (Chapter 9).",
            imports: ["HashTreeCollections"]
        ),
        law(
            "TreeDictionary", "mapValues functor identity", "d.mapValues { $0 } == d",
            "var d = TreeDictionary<Int, Int>(); for (key, value) in randDict() { d[key] = value }; "
                + "return d.mapValues { $0 } == d",
            imports: ["HashTreeCollections"]
        )
    ]

    // MARK: - Heap (HeapModule) — model-based (no protocol row applies)

    private static let heapLaws: [KnownProperty] = [
        law(
            "Heap", "popMin drains in sorted order (model-based)", "draining popMin() == unordered.sorted()",
            "let arr = randArr(); var heap = Heap(arr); var out = [Int](); "
                + "while let least = heap.popMin() { out.append(least) }; return out == arr.sorted()",
            note: "Heap is not even a Sequence, so no appendix row applies — its laws are oracle laws "
                + "against the sorted-array model (the smallest model-vs-SUT instance).",
            imports: ["HeapModule"]
        ),
        law(
            "Heap", "min / max agree with the model", "heap.min == arr.min(), heap.max == arr.max()",
            "let arr = randArr(); if arr.isEmpty { return true }; let heap = Heap(arr); "
                + "return heap.min == arr.min() && heap.max == arr.max()",
            imports: ["HeapModule"]
        )
    ]

    static let collectionsLaws: [KnownProperty] =
        dequeLaws + orderedLaws + bitSetLaws + treeLaws + heapLaws
}
