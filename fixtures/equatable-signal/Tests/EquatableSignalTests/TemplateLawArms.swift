import OrderedCollections
import Testing

/// Runs the fixture's three projection mutants against the law
/// `SequenceViewModelLawTemplate` **actually emits**, rather than against the
/// hand-written model the original measurement used.
///
/// ## Why this is not the same measurement as `CollectionArms.swift`
///
/// Those arms score `left == right ⟺ model(left) == model(right)` with `model`
/// a hand-written property on the storage struct — `\.elements`,
/// `\.logicalBits`, `\.logicalOrder`. That measured whether a model law *of
/// some kind* catches the bugs, which is what justified building a template.
///
/// The shipped template cannot write those properties. It has no semantic
/// resolution and no annotation to read, so its abstraction function is the one
/// the type already publishes: its own `Sequence` conformance. It emits
///
///     (a == b) == a.elementsEqual(b)
///
/// which is `Array(a) == Array(b)` for a single element type. Whether *that*
/// law catches the same three bugs is a separate question from whether the
/// hand-written one does, and it is the question that decides whether the
/// template earns its Strong tier.
///
/// ## The oracle-independence condition, made explicit
///
/// Findings §4.4: *"a test's oracle must be independent of the thing under
/// test."* Here the subject is `==` and the oracle is the `Sequence`
/// conformance, so the mutants below get a **correct** iteration order. That is
/// not a convenience — it is what the real types do. `Deque`'s
/// `RandomAccessCollection` conformance walks the ring buffer correctly whatever
/// `==` does; `BitArray`'s iteration yields exactly `count` bits whether or not
/// `==` masks its padding. A mutant whose iteration were broken the same way as
/// its `==` would make the law blind, and that would be a fixture defect rather
/// than a finding about the template.

// MARK: - The sequence views the real types publish

/// `OrderedSet` is a `RandomAccessCollection` over its deduped element array.
extension FaithfulOrderedSet: Sequence {
    func makeIterator() -> IndexingIterator<[Int]> { storage.elements.makeIterator() }
}

extension UnorderedMutantSet: Sequence {
    func makeIterator() -> IndexingIterator<[Int]> { storage.elements.makeIterator() }
}

/// `BitArray` iterates exactly `count` bits — padding above the logical count is
/// never yielded, which is precisely the information `RawStorageBits.==` lets in.
extension MaskedBits: Sequence {
    func makeIterator() -> IndexingIterator<[Bool]> { storage.logicalBits.makeIterator() }
}

extension RawStorageBits: Sequence {
    func makeIterator() -> IndexingIterator<[Bool]> { storage.logicalBits.makeIterator() }
}

/// `Deque` iterates in logical order, rotating through the ring buffer's head.
extension FaithfulRingDeque: Sequence {
    func makeIterator() -> IndexingIterator<[Int]> { storage.logicalOrder.makeIterator() }
}

extension UnrotatedRingDeque: Sequence {
    func makeIterator() -> IndexingIterator<[Int]> { storage.logicalOrder.makeIterator() }
}

// MARK: - The arms

@Suite("The law the template emits, against the same three mutants")
struct TemplateEmittedLawArms {

    /// `(a == b) == a.elementsEqual(b)`, spelled as the driver wants it. For a
    /// single element type `Array(a) == Array(b)` and `a.elementsEqual(b)` are
    /// the same predicate, so this is the emitted law verbatim.
    private func sequenceViewLaw<Subject: Sequence & Equatable>(
        samplePair: (inout SeededGenerator) -> (Subject, Subject),
        describe: @escaping (Subject) -> String
    ) -> ModelLawOutcome where Subject.Element: Equatable {
        checkModelLaw(
            samplePair: samplePair,
            areEqual: { $0 == $1 },
            model: { Array($0) },
            describe: describe
        )
    }

    @Test("OrderedSet — the order-insensitive mutant is caught by the EMITTED law")
    func orderedSetMutantIsCaught() {
        let faithful = sequenceViewLaw(
            samplePair: { generator in
                let pair = ProjectionMutantArms.orderedSetPair(&generator)
                return (FaithfulOrderedSet(storage: pair.0), FaithfulOrderedSet(storage: pair.1))
            },
            describe: { "\($0.storage.elements)" }
        )
        reportModelLaw("FaithfulOrderedSet / emitted law", faithful)
        #expect(faithful.passed, "the emitted law must hold on a correct ==")

        let mutant = sequenceViewLaw(
            samplePair: { generator in
                let pair = ProjectionMutantArms.orderedSetPair(&generator)
                return (UnorderedMutantSet(storage: pair.0), UnorderedMutantSet(storage: pair.1))
            },
            describe: { "\($0.storage.elements)" }
        )
        reportModelLaw("UnorderedMutantSet / emitted law", mutant)
        #expect(!mutant.passed, "the emitted law is what has to catch this")
    }

    @Test("BitArray — the raw-storage mutant is caught by the EMITTED law")
    func bitArrayMutantIsCaught() {
        let faithful = sequenceViewLaw(
            samplePair: { generator in
                let pair = ProjectionMutantArms.wordBackedPair(&generator)
                return (MaskedBits(storage: pair.0), MaskedBits(storage: pair.1))
            },
            describe: { "count=\($0.storage.bitCount) words=\($0.storage.words)" }
        )
        reportModelLaw("MaskedBits / emitted law", faithful)
        #expect(faithful.passed)

        let mutant = sequenceViewLaw(
            samplePair: { generator in
                let pair = ProjectionMutantArms.wordBackedPair(&generator)
                return (RawStorageBits(storage: pair.0), RawStorageBits(storage: pair.1))
            },
            describe: { "count=\($0.storage.bitCount) words=\($0.storage.words)" }
        )
        reportModelLaw("RawStorageBits / emitted law", mutant)
        #expect(!mutant.passed, "this is the SHIPPED BitArray body — the law must reach it")
    }

    @Test("Deque — the unrotated mutant is caught by the EMITTED law")
    func dequeMutantIsCaught() {
        let faithful = sequenceViewLaw(
            samplePair: { generator in
                let pair = ProjectionMutantArms.ringBufferPair(&generator)
                return (FaithfulRingDeque(storage: pair.0), FaithfulRingDeque(storage: pair.1))
            },
            describe: { "\($0.storage.logicalOrder)" }
        )
        reportModelLaw("FaithfulRingDeque / emitted law", faithful)
        #expect(faithful.passed)

        let mutant = sequenceViewLaw(
            samplePair: { generator in
                let pair = ProjectionMutantArms.ringBufferPair(&generator)
                return (UnrotatedRingDeque(storage: pair.0), UnrotatedRingDeque(storage: pair.1))
            },
            describe: { "\($0.storage.logicalOrder)" }
        )
        reportModelLaw("UnrotatedRingDeque / emitted law", mutant)
        #expect(!mutant.passed)
    }

    // MARK: - The discriminator's justification, run rather than argued

    /// The reason `OrderedCarrierDiscriminator` exists. `Set` is a `Sequence`
    /// whose iteration order is a function of the hash seed and the table's
    /// capacity, not of the value — so the emitted law is **false** for it, and
    /// a template without the discriminator would propose a law that a correct
    /// implementation fails.
    ///
    /// **The one arm in this fixture that is deliberately non-deterministic.**
    /// Everything else runs off a seeded LCG so a counterexample replays from
    /// the seed alone. Here the divergence count moves run to run — 4,042 and
    /// 4,136 on two consecutive runs — because Swift randomises the hash seed
    /// per process, which is the very property being demonstrated. Asserting a
    /// fixed count would be asserting that the seed is fixed, which it is not.
    ///
    /// Deliberately built through different capacities rather than different
    /// insertion orders: two small `Set`s with identical contents and identical
    /// capacity usually *do* iterate identically, which is exactly why this
    /// hazard is easy to miss by hand.
    @Test("Set — the emitted law is FALSE, which is what the discriminator prevents")
    func setWouldTakeAFalseLaw() {
        var generator = SeededGenerator(seed: 0x5EED_1234)
        var divergences = 0
        var firstWitness: String?

        for _ in 1 ... 5_000 {
            let values = (0 ..< generator.nextInt(in: 2 ... 6)).map { _ in
                generator.nextInt(in: 0 ... 40)
            }
            var left = Set<Int>()
            for value in values { left.insert(value) }

            // Same contents, reached with a much larger table.
            var right = Set<Int>(minimumCapacity: 128)
            for value in values.reversed() { right.insert(value) }

            if left == right, !Array(left).elementsEqual(Array(right)) {
                divergences += 1
                if firstWitness == nil {
                    firstWitness = "left == right, but \(Array(left)) != \(Array(right))"
                }
            }
        }

        print("  [Set / emitted law] \(divergences) of 5000 pairs violate the law"
            + (firstWitness.map { "; e.g. \($0)" } ?? ""))
        // If this ever reaches zero the arm has stopped demonstrating anything: the law
        // is still false for Set, the generator has just stopped witnessing it.
        #expect(divergences > 0)
    }
}
