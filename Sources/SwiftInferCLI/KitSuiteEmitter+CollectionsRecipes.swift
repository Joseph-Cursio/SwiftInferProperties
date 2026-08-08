import Foundation

// The §4a decision from `docs/plans/kit-suite-backtest-plan.md`, taken 2026-08-08.
extension KitSuiteEmitter {

    /// The kit's `PropertyLawCollections` recipe for a carrier the strategist could not
    /// derive a generator for — **advisory text only**.
    ///
    /// ## The decision this encodes (plan §4a)
    ///
    /// §3b measured that **7 of the 8 public swift-collections types the emitter reports as
    /// "BLOCKED on a generator" already have hand-written generators in the kit**, in its
    /// opt-in `PropertyLawCollections` product. The emitter did not know that product existed,
    /// which made it the single largest lever on the blocked count — and a design decision
    /// rather than a bug fix, because the obvious version of it is wrong three ways:
    ///
    /// - It would make the *live* path carrier-name-aware — a curated table of
    ///   `TreeSet -> recipe`. That is the `curatedVerbs` posture applied to types, against the
    ///   standing line that *the kit needs a type, `discover` works from shape*.
    /// - It would add a dependency the user may not want. `PropertyLawCollections` exists
    ///   **precisely** to keep swift-collections off the main `PropertyLawKit` line, so
    ///   emitting a live call to it silently widens the reader's graph.
    /// - It only helps carriers the kit already curated, which is the opposite of the transfer
    ///   property the `[reference]` backlog is measured by — *success is carriers reached
    ///   OUTSIDE the catalog*.
    ///
    /// So the recipe is emitted as a **comment on an entry that is already commented out**,
    /// and this table is read by ``KitSuiteEmitter/blockedBlock(_:suites:reason:carrierName:)``
    /// and by nothing else. A blocked entry is inert text a human reads; naming the one-liner
    /// there costs no dependency, no live-path name-keying, and no behaviour.
    ///
    /// **It also closes §3b's finding 3.** For `Deque` the strategist derives
    /// `Gen<Int>.int(in: -10_000...10_000).map { Deque(minimumCapacity: $0) }` — every value an
    /// *empty* deque differing only in reserved capacity, which is not part of the value, so
    /// the Hashable and Sequence laws would pass over a constant. The reader who follows this
    /// comment gets a generator that varies the value instead; the reader who hand-rolls one
    /// from the `.gen()` hint may well reproduce the vacuous version.
    ///
    /// > **Corrected 2026-08-08, kit `3.27.1` (`595e400`) — the conclusion stands, its
    /// > evidence does not.** The paragraph above was written against kit `91e09a2`, and the
    /// > kit moved the same afternoon. `minimumCapacity` is now in the public
    /// > `InitializerBasedDerivation.capacityHintLabels`, and `isCapacityOnly` declines any
    /// > initializer whose parameters are ALL capacity-shaped — so the strategist no longer
    /// > derives that vacuous generator, it returns the carrier to `.todo`. The recipe below
    /// > is therefore *more* load-bearing than when it was written, not less: the reader now
    /// > arrives here holding a `.gen()` hint rather than a wrong generator, and the kit's own
    /// > decline comment says as much — *"Declining here returns the carrier to `.todo`, where
    /// > the message already tells the user to supply `gen()` … which the kit's own
    /// > `PropertyLawCollections` recipes then satisfy."* Do not read the sentence above as a
    /// > live description of strategist behaviour; it is the measurement that motivated this
    /// > table.
    ///
    /// **Prior art, and it cuts the other way.** `StrategistDispatchEmitter.curatedOCRecipes`
    /// already keys on carrier names — 8 entries — and hand-writes generators for
    /// `OrderedSet<Int>`, `OrderedDictionary<Int, Int>` and `Deque<Int>`, three of the seven
    /// below. That concession is not the same as this one and does not license widening it:
    /// there the recipe must be *live* because the emitted stub has to run, and the other five
    /// entries are views (`.UnorderedView`, `.Elements.SubSequence`, …) the kit ships nothing
    /// for. Here the entry never runs. The duplication is recorded rather than fixed — folding
    /// those three onto the kit is a verify-path change with its own dependency question.
    ///
    /// - Parameter carrierName: the name as *written* — `Deque<Int>`, not `Deque`. The
    ///   emitter names generic carriers concretely (`ConcreteInstantiation.rendered`), and the
    ///   kit binds its element types to `Int` for the same reason, so the two spellings meet.
    /// - Returns: the recipe expression, or `nil` for a carrier the kit does not cover.
    static func propertyLawCollectionsRecipe(for carrierName: String) -> String? {
        propertyLawCollectionsRecipes[carrierName]
    }

    /// Read off `SwiftPropertyLaws@91e09a2 Sources/PropertyLawCollections/*Generators.swift`,
    /// **re-verified at `595e400` (3.27.1) on 2026-08-08**: the five commits between the two
    /// SHAs touch `PropertyLawCore/InitializerBasedDerivation.swift` only, and
    /// `git diff 91e09a2..595e400 -- Sources/PropertyLawCollections/` is empty, so every
    /// recipe string below is unchanged. The original SHA is kept as the provenance of the
    /// reading; the second is the last commit it was checked against.
    /// Every recipe's arguments are fully defaulted and every one returns
    /// `Generator<Value, some SendableSequenceType>`, which is exactly the `using:` parameter
    /// of `check<Protocol>PropertyLaws` — so the emitted line is paste-and-run once the
    /// product is added, not a sketch.
    ///
    /// **`BitArray` is the eighth type and is deliberately absent.** The kit ships no
    /// generator for it, so it must keep the plain `.gen()` hint rather than borrow a
    /// neighbour's — a reader who sees six of seven siblings answered and reads the seventh as
    /// answered too would be told to call something that does not exist.
    private static let propertyLawCollectionsRecipes: [String: String] = [
        "Deque<Int>": "Gen<Deque<Int>>.smallIntDeque()",
        "OrderedSet<Int>": "Gen<OrderedSet<Int>>.smallIntOrderedSet()",
        "OrderedDictionary<Int, Int>":
            "Gen<OrderedDictionary<Int, Int>>.smallIntOrderedDictionary()",
        "TreeSet<Int>": "Gen<TreeSet<Int>>.smallIntTreeSet()",
        "TreeDictionary<Int, Int>": "Gen<TreeDictionary<Int, Int>>.smallIntTreeDictionary()",
        "BitSet": "Gen<BitSet>.smallBitSet()",
        "Heap<Int>": "Gen<Heap<Int>>.smallIntHeap()"
    ]
}
