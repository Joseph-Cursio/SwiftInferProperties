import PropertyBased

/// Reproductions of three `swift-collections` `==` bodies, each paired with the
/// bug that body's correctness silently depends on *not* having.
///
/// All three real bodies are **projections** of the stored fields, which is why
/// they are here: the swift-numerics half of this fixture predicted that a
/// projection cannot be refuted by the Equatable laws, and these are the real
/// public conformances that let the prediction be measured rather than argued.
///
/// Bodies reproduced (swift-collections @ `899809d3`):
///
/// - `OrderedSet+Equatable`  → `left._elements == right._elements`
/// - `BitArray+Equatable`    → `left._count == right._count && left._storage == right._storage`
/// - `Deque+Equatable`       → count guard, referential fast path, then `elementsEqual`

// MARK: - 1. OrderedSet — order sensitivity

/// Reproduction of `OrderedSet`'s storage: a deduped array in insertion order.
struct InsertionOrderedInts: Sendable {
    var elements: [Int]

    init(_ source: [Int]) {
        var seen = Set<Int>()
        var kept: [Int] = []
        for value in source where seen.insert(value).inserted {
            kept.append(value)
        }
        self.elements = kept
    }
}

/// Faithful. `OrderedSet.==` is order-*sensitive*, and its doc comment says so
/// explicitly: "This operator implements different behavior than the
/// `isEqualSet(to:)` method -- the latter implements an unordered comparison."
struct FaithfulOrderedSet: Equatable, Sendable, CustomStringConvertible {
    var storage: InsertionOrderedInts

    static func == (left: Self, right: Self) -> Bool {
        left.storage.elements == right.storage.elements
    }

    var description: String { "\(storage.elements)" }
}

/// Mutant — compares as an unordered set. This is not a strawman: it is
/// `isEqualSet(to:)`'s semantics, which the real type also ships, one method
/// away, under a name a reader could easily reach for by mistake.
struct UnorderedMutantSet: Equatable, Sendable, CustomStringConvertible {
    var storage: InsertionOrderedInts

    static func == (left: Self, right: Self) -> Bool {
        Set(left.storage.elements) == Set(right.storage.elements)
    }

    var description: String { "\(storage.elements)" }
}

// MARK: - 2. BitArray — padding bits above the logical count

/// Reproduction of `BitArray`'s storage: words plus a logical bit count that
/// may stop partway through the final word. Bits at or above `bitCount` are
/// *padding* and carry no meaning — `BitArray.swift`'s own comment says
/// "`_count` may [be] less than the number of bits in `_storage` if the last
/// word isn't fully filled."
///
/// An 8-bit word keeps the arithmetic readable; the real type uses `UInt`.
struct WordBackedBits: Sendable {
    static let wordBits = 8

    var words: [UInt8]
    var bitCount: Int

    /// The reference definition of the value: exactly `bitCount` bits, with no
    /// representation detail surviving.
    var logicalBits: [Bool] {
        (0 ..< bitCount).map { index in
            (words[index / Self.wordBits] >> (index % Self.wordBits)) & 1 == 1
        }
    }

    /// `words` with every padding bit forced to zero.
    var maskedWords: [UInt8] {
        words.enumerated().map { offset, word in
            let lowBit = offset * Self.wordBits
            if bitCount >= lowBit + Self.wordBits { return word }
            if bitCount <= lowBit { return 0 }
            let keep = bitCount - lowBit
            return word & UInt8((1 << keep) - 1)
        }
    }
}

/// Faithful *to the intended semantics* — canonicalises padding before
/// comparing. Note this is **not** what swift-collections wrote.
struct MaskedBits: Equatable, Sendable, CustomStringConvertible {
    var storage: WordBackedBits

    static func == (left: Self, right: Self) -> Bool {
        left.storage.bitCount == right.storage.bitCount
            && left.storage.maskedWords == right.storage.maskedWords
    }

    var description: String {
        "count=\(storage.bitCount) words=\(storage.words)"
    }
}

/// The **actual** `BitArray+Equatable.swift` body: count guard, then a raw
/// storage compare. Correct only while every mutating path keeps padding bits
/// zeroed — an invariant `==` itself does not enforce.
struct RawStorageBits: Equatable, Sendable, CustomStringConvertible {
    var storage: WordBackedBits

    static func == (left: Self, right: Self) -> Bool {
        left.storage.bitCount == right.storage.bitCount
            && left.storage.words == right.storage.words
    }

    var description: String {
        "count=\(storage.bitCount) words=\(storage.words)"
    }
}

// MARK: - 3. Deque — the ring buffer's head offset

/// Reproduction of `Deque`'s storage: a fixed-capacity ring buffer plus a head
/// offset, so the logical order wraps around the end of the buffer.
struct RingBuffer: Sendable {
    var slots: [Int]
    var head: Int
    var count: Int

    /// The reference definition: elements in logical order, head-relative.
    var logicalOrder: [Int] {
        guard !slots.isEmpty else { return [] }
        return (0 ..< count).map { offset in slots[(head + offset) % slots.count] }
    }
}

/// Faithful — compares logical order, which is what `Deque.elementsEqual` does.
struct FaithfulRingDeque: Equatable, Sendable, CustomStringConvertible {
    var storage: RingBuffer

    static func == (left: Self, right: Self) -> Bool {
        left.storage.count == right.storage.count
            && left.storage.logicalOrder == right.storage.logicalOrder
    }

    var description: String {
        "\(storage.logicalOrder) [slots=\(storage.slots) head=\(storage.head)]"
    }
}

/// Mutant — compares the raw buffer and forgets to rotate by `head`. The
/// canonical ring-buffer defect: two deques holding the same elements in the
/// same logical order compare unequal because one has wrapped.
struct UnrotatedRingDeque: Equatable, Sendable, CustomStringConvertible {
    var storage: RingBuffer

    static func == (left: Self, right: Self) -> Bool {
        left.storage.count == right.storage.count
            && left.storage.slots == right.storage.slots
    }

    var description: String {
        "\(storage.logicalOrder) [slots=\(storage.slots) head=\(storage.head)]"
    }
}

// MARK: - Generators for the Equatable-law arms

/// Alphabet `0...3` and length `0...3` deliberately: the interesting inputs for
/// an order-sensitivity law are *permutations of each other*, and a wider
/// alphabet makes two independently drawn samples share a member-set far too
/// rarely to matter. Narrowing on purpose, per the repo's collision guidance.
func orderedSetStorage() -> Generator<InsertionOrderedInts, some SendableSequenceType> {
    Gen<Int>.int(in: 0 ... 3).array(of: 0 ... 3).map { InsertionOrderedInts($0) }
}

/// One 8-bit word with `bitCount` in `1...7`, so there is *always* at least one
/// padding bit for the raw-storage mutant to trip over.
func wordBackedBitsStorage() -> Generator<WordBackedBits, some SendableSequenceType> {
    zip(Gen<Int>.int(in: 1 ... 7), Gen<Int>.int(in: 0 ... 255))
        .map { bitCount, word -> WordBackedBits in
            WordBackedBits(words: [UInt8(word)], bitCount: bitCount)
        }
}

/// Capacity fixed at 4 so `head` and `count` both range over a small space and
/// two samples routinely share a logical order at different heads.
func ringBufferStorage() -> Generator<RingBuffer, some SendableSequenceType> {
    zip(
        Gen<Int>.int(in: 0 ... 3).array(of: 4 ... 4),
        Gen<Int>.int(in: 0 ... 3),
        Gen<Int>.int(in: 0 ... 4)
    )
    .map { slots, head, count -> RingBuffer in
        RingBuffer(slots: slots, head: head, count: count)
    }
}
