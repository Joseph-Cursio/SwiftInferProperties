import BitCollections
import DequeModule
import HashTreeCollections
import OrderedCollections
import PropertyBased
import PropertyLawCollections
import PropertyLawKit
import Testing

/// The swift-collections half of the fixture: 49 public `Equatable`
/// conformances instead of swift-numerics' 2, so the discriminator can be
/// *scored* rather than illustrated.
///
/// Group A points the real law suite at the real types — the no-regression
/// baseline. Group B is the measurement: three real projection-class `==`
/// bodies, each reproduced with the bug its correctness depends on not having,
/// run through **both** the Equatable laws and the model law.
@Suite("swift-collections — real types")
struct RealCollectionTypeArms {
    @Test("OrderedSet<Int>")
    func orderedSet() async {
        let violations = await EquatableSignalTests.equatableViolations(
            "OrderedSet<Int>",
            Gen<OrderedSet<Int>>.smallIntOrderedSet()
        )
        #expect(violations.isEmpty)
    }

    @Test("OrderedDictionary<Int, Int>")
    func orderedDictionary() async {
        let violations = await EquatableSignalTests.equatableViolations(
            "OrderedDictionary<Int, Int>",
            Gen<OrderedDictionary<Int, Int>>.smallIntOrderedDictionary()
        )
        #expect(violations.isEmpty)
    }

    @Test("BitSet")
    func bitSet() async {
        let violations = await EquatableSignalTests.equatableViolations(
            "BitSet",
            Gen<BitSet>.smallBitSet()
        )
        #expect(violations.isEmpty)
    }

    @Test("Deque<Int>")
    func deque() async {
        let violations = await EquatableSignalTests.equatableViolations(
            "Deque<Int>",
            Gen<Deque<Int>>.smallIntDeque()
        )
        #expect(violations.isEmpty)
    }

    @Test("TreeSet<Int>")
    func treeSet() async {
        let violations = await EquatableSignalTests.equatableViolations(
            "TreeSet<Int>",
            Gen<TreeSet<Int>>.smallIntTreeSet()
        )
        #expect(violations.isEmpty)
    }

    @Test("TreeDictionary<Int, Int>")
    func treeDictionary() async {
        let violations = await EquatableSignalTests.equatableViolations(
            "TreeDictionary<Int, Int>",
            Gen<TreeDictionary<Int, Int>>.smallIntTreeDictionary()
        )
        #expect(violations.isEmpty)
    }
}

/// Each arm asserts the same two-part claim: the Equatable law suite is **blind**
/// to the mutant, and the model law **catches** it. Both halves matter — the
/// first is what makes a conformance-keyed template worthless here, the second is
/// what the template should propose instead.
@Suite("swift-collections — projection mutants")
struct ProjectionMutantArms {
    // MARK: - 1. OrderedSet: order sensitivity

    @Test("OrderedSet — order-insensitive mutant: laws blind, model law catches")
    func orderedSetOrderMutant() async {
        let faithfulLaws = await EquatableSignalTests.equatableViolations(
            "FaithfulOrderedSet",
            orderedSetStorage().map { FaithfulOrderedSet(storage: $0) }
        )
        #expect(faithfulLaws.isEmpty)

        let mutantLaws = await EquatableSignalTests.equatableViolations(
            "UnorderedMutantSet",
            orderedSetStorage().map { UnorderedMutantSet(storage: $0) }
        )
        #expect(mutantLaws.isEmpty, "a Set comparison is still an equivalence relation")

        let faithfulModel = checkModelLaw(
            samplePair: Self.orderedSetPair,
            areEqual: { FaithfulOrderedSet(storage: $0) == FaithfulOrderedSet(storage: $1) },
            model: \.elements,
            describe: { "\($0.elements)" }
        )
        reportModelLaw("FaithfulOrderedSet", faithfulModel)
        #expect(faithfulModel.passed)

        let mutantModel = checkModelLaw(
            samplePair: Self.orderedSetPair,
            areEqual: { UnorderedMutantSet(storage: $0) == UnorderedMutantSet(storage: $1) },
            model: \.elements,
            describe: { "\($0.elements)" }
        )
        reportModelLaw("UnorderedMutantSet", mutantModel)
        #expect(!mutantModel.passed, "the model law is what has to catch this")
    }

    /// Half the pairs are permutations of each other — the collision an
    /// order-sensitivity law needs.
    static func orderedSetPair(
        _ generator: inout SeededGenerator
    ) -> (InsertionOrderedInts, InsertionOrderedInts) {
        let left = InsertionOrderedInts(
            (0 ..< generator.nextInt(in: 0 ... 3)).map { _ in generator.nextInt(in: 0 ... 3) }
        )
        guard generator.nextBool() else {
            let right = InsertionOrderedInts(
                (0 ..< generator.nextInt(in: 0 ... 3)).map { _ in generator.nextInt(in: 0 ... 3) }
            )
            return (left, right)
        }
        var permuted = left.elements
        if permuted.count > 1 {
            let first = generator.nextInt(in: 0 ... permuted.count - 1)
            let second = generator.nextInt(in: 0 ... permuted.count - 1)
            permuted.swapAt(first, second)
        }
        return (left, InsertionOrderedInts(permuted))
    }

    // MARK: - 2. BitArray: padding bits above the logical count

    @Test("BitArray — raw-storage body: laws blind, model law catches")
    func bitArrayPaddingMutant() async {
        let faithfulLaws = await EquatableSignalTests.equatableViolations(
            "MaskedBits",
            wordBackedBitsStorage().map { MaskedBits(storage: $0) }
        )
        #expect(faithfulLaws.isEmpty)

        let mutantLaws = await EquatableSignalTests.equatableViolations(
            "RawStorageBits (the shipped body)",
            wordBackedBitsStorage().map { RawStorageBits(storage: $0) }
        )
        #expect(mutantLaws.isEmpty, "a raw (count, words) compare is still an equivalence relation")

        let faithfulModel = checkModelLaw(
            samplePair: Self.wordBackedPair,
            areEqual: { MaskedBits(storage: $0) == MaskedBits(storage: $1) },
            model: \.logicalBits,
            describe: { "count=\($0.bitCount) words=\($0.words)" }
        )
        reportModelLaw("MaskedBits", faithfulModel)
        #expect(faithfulModel.passed)

        let mutantModel = checkModelLaw(
            samplePair: Self.wordBackedPair,
            areEqual: { RawStorageBits(storage: $0) == RawStorageBits(storage: $1) },
            model: \.logicalBits,
            describe: { "count=\($0.bitCount) words=\($0.words)" }
        )
        reportModelLaw("RawStorageBits (the shipped body)", mutantModel)
        #expect(!mutantModel.passed, "the model law is what has to catch this")
    }

    /// Half the pairs share their logical bits and differ only in padding — the
    /// state a mutating method that forgot to re-mask would leave behind.
    static func wordBackedPair(
        _ generator: inout SeededGenerator
    ) -> (WordBackedBits, WordBackedBits) {
        let bitCount = generator.nextInt(in: 1 ... 7)
        let leftWord = UInt8(generator.nextInt(in: 0 ... 255))
        let left = WordBackedBits(words: [leftWord], bitCount: bitCount)
        guard generator.nextBool() else {
            let right = WordBackedBits(
                words: [UInt8(generator.nextInt(in: 0 ... 255))],
                bitCount: bitCount
            )
            return (left, right)
        }
        let mask = UInt8((1 << bitCount) - 1)
        let paddingNoise = UInt8(generator.nextInt(in: 0 ... 255)) & ~mask
        let rightWord = (leftWord & mask) | paddingNoise
        return (left, WordBackedBits(words: [rightWord], bitCount: bitCount))
    }

    // MARK: - 3. Deque: the ring buffer's head offset

    @Test("Deque — unrotated ring-buffer mutant: laws blind, model law catches")
    func dequeRotationMutant() async {
        let faithfulLaws = await EquatableSignalTests.equatableViolations(
            "FaithfulRingDeque",
            ringBufferStorage().map { FaithfulRingDeque(storage: $0) }
        )
        #expect(faithfulLaws.isEmpty)

        let mutantLaws = await EquatableSignalTests.equatableViolations(
            "UnrotatedRingDeque",
            ringBufferStorage().map { UnrotatedRingDeque(storage: $0) }
        )
        #expect(mutantLaws.isEmpty, "a raw (count, slots) compare is still an equivalence relation")

        let faithfulModel = checkModelLaw(
            samplePair: Self.ringBufferPair,
            areEqual: { FaithfulRingDeque(storage: $0) == FaithfulRingDeque(storage: $1) },
            model: \.logicalOrder,
            describe: { "\($0.logicalOrder) [slots=\($0.slots) head=\($0.head)]" }
        )
        reportModelLaw("FaithfulRingDeque", faithfulModel)
        #expect(faithfulModel.passed)

        let mutantModel = checkModelLaw(
            samplePair: Self.ringBufferPair,
            areEqual: { UnrotatedRingDeque(storage: $0) == UnrotatedRingDeque(storage: $1) },
            model: \.logicalOrder,
            describe: { "\($0.logicalOrder) [slots=\($0.slots) head=\($0.head)]" }
        )
        reportModelLaw("UnrotatedRingDeque", mutantModel)
        #expect(!mutantModel.passed, "the model law is what has to catch this")
    }

    /// Half the pairs hold the same elements in the same logical order at
    /// *different* head offsets — a deque that has wrapped versus one that
    /// hasn't.
    static func ringBufferPair(
        _ generator: inout SeededGenerator
    ) -> (RingBuffer, RingBuffer) {
        let capacity = 4
        let count = generator.nextInt(in: 0 ... capacity)
        let logical = (0 ..< count).map { _ in generator.nextInt(in: 0 ... 3) }
        let left = Self.ringBuffer(logical, head: generator.nextInt(in: 0 ... 3), capacity: capacity)
        guard generator.nextBool() else {
            let otherCount = generator.nextInt(in: 0 ... capacity)
            let otherLogical = (0 ..< otherCount).map { _ in generator.nextInt(in: 0 ... 3) }
            let right = Self.ringBuffer(
                otherLogical,
                head: generator.nextInt(in: 0 ... 3),
                capacity: capacity
            )
            return (left, right)
        }
        let right = Self.ringBuffer(logical, head: generator.nextInt(in: 0 ... 3), capacity: capacity)
        return (left, right)
    }

    static func ringBuffer(_ logical: [Int], head: Int, capacity: Int) -> RingBuffer {
        var slots = Array(repeating: 0, count: capacity)
        for (offset, value) in logical.enumerated() {
            slots[(head + offset) % capacity] = value
        }
        return RingBuffer(slots: slots, head: head, count: logical.count)
    }
}
