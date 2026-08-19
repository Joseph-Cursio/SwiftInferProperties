import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **Guards the §4a decision** (`plans/kit-suite-backtest-plan.md`): a blocked
/// swift-collections carrier names the kit generator that already exists, and the live path
/// never does.
///
/// The two directions fail differently, which is why both are asserted. A missing hint is
/// under-service — the reader hand-writes a `gen()` the kit already ships, and §3b measured
/// that the hand-written one can be *vacuous* (`Deque(minimumCapacity:)` varies nothing that
/// is part of the value). A hint that leaked into the live path is worse: it would compile
/// only for a reader who added an opt-in product that exists precisely to keep
/// swift-collections off the main `PropertyLawKit` line.
@Suite("Kit-suite PropertyLawCollections recipes")
struct KitSuiteCollectionsRecipeTests {

    private func finding(
        _ typeName: String,
        conformances: [String],
        laws: Set<KnownProperty> = [.equatableReflexive]
    ) -> ProtocolCoverageAudit.Finding {
        ProtocolCoverageAudit.Finding(
            typeName: typeName,
            coveringConformance: conformances.min() ?? "",
            standing: .assumed,
            coveredLaws: laws,
            declaredCoveringConformances: conformances.sorted()
        )
    }

    /// A carrier whose stored member the strategist cannot derive, so it lands blocked.
    private func opaqueShape(_ name: String) -> TypeShape {
        TypeShape(
            name: name, kind: .struct, inheritedTypes: ["Equatable"], hasUserGen: false,
            storedMembers: [StoredMember(name: "inner", typeName: "SomeUnknownType")]
        )
    }

    // MARK: - The table

    @Test("every covered carrier is spelled the way the emitter writes it")
    func tableKeysMatchTheEmittedSpelling() {
        // `ConcreteInstantiation.rendered` substitutes `Int` per generic parameter, and the
        // kit binds its element types to `Int` for the same reason. These are the seven
        // spellings where those two conventions meet; a mismatch here is a silent no-op.
        #expect(
            KitSuiteEmitter.propertyLawCollectionsRecipe(for: "Deque<Int>")
                == "Gen<Deque<Int>>.smallIntDeque()"
        )
        #expect(
            KitSuiteEmitter.propertyLawCollectionsRecipe(for: "TreeDictionary<Int, Int>")
                == "Gen<TreeDictionary<Int, Int>>.smallIntTreeDictionary()"
        )
        #expect(KitSuiteEmitter.propertyLawCollectionsRecipe(for: "BitSet") != nil)
        // The bare generic name is what the emitter used to write and no longer does. It must
        // not match — a hint keyed to a spelling nothing emits is a hint nobody sees.
        #expect(KitSuiteEmitter.propertyLawCollectionsRecipe(for: "Deque") == nil)
    }

    /// **`BitArray` is the eighth public type and the kit ships no generator for it.**
    /// Six of its seven siblings being answered is exactly the condition under which a reader
    /// skims and assumes the seventh was too.
    @Test("BitArray keeps the plain gen() hint")
    func bitArrayIsNotGivenANeighboursRecipe() {
        #expect(KitSuiteEmitter.propertyLawCollectionsRecipe(for: "BitArray") == nil)
        let block = KitSuiteEmitter.blockedBlock(
            finding("BitArray", conformances: ["Equatable"]),
            suites: ["Equatable"],
            reason: "no generator",
            carrierName: "BitArray"
        )
        #expect(block.contains("using: BitArray.gen()"))
        #expect(!block.contains("PropertyLawCollections"))
    }

    // MARK: - The blocked entry

    @Test("a blocked collections carrier names the product and the recipe")
    func blockedCarrierNamesTheKitRecipe() {
        let block = KitSuiteEmitter.blockedBlock(
            finding("Deque", conformances: ["Equatable", "Hashable"]),
            suites: ["Equatable", "Hashable"],
            reason: "the strategist returned .todo",
            carrierName: "Deque<Int>"
        )
        // Naming the product is the load-bearing half: the recipe alone would not tell a
        // reader that it lives behind an opt-in dependency they have not added.
        #expect(block.contains("PropertyLawCollections"))
        #expect(block.contains("Gen<Deque<Int>>.smallIntDeque()"))
        // The commented call uses the recipe rather than the `.gen()` a reader would have to
        // write themselves — both suites, not just the first.
        #expect(
            block.contains(
                "checkEquatablePropertyLaws(for: Deque<Int>.self, "
                    + "using: Gen<Deque<Int>>.smallIntDeque())"
            )
        )
        #expect(
            block.contains(
                "checkHashablePropertyLaws(for: Deque<Int>.self, "
                    + "using: Gen<Deque<Int>>.smallIntDeque())"
            )
        )
        #expect(!block.contains(".gen()"))
        // The entry is still commented out. The hint changes what a reader is told to write,
        // never whether the emitted file calls it.
        for line in block.split(separator: "\n") {
            #expect(line.trimmingCharacters(in: .whitespaces).hasPrefix("//"))
        }
    }

    @Test("a carrier the kit does not cover is unchanged")
    func nonCollectionsCarrierKeepsItsHint() {
        let block = KitSuiteEmitter.blockedBlock(
            finding("Opaque", conformances: ["Equatable"]),
            suites: ["Equatable"],
            reason: "the strategist returned .todo",
            carrierName: "Opaque"
        )
        #expect(block.contains("using: Opaque.gen()"))
        #expect(!block.contains("PropertyLawCollections"))
    }

    // MARK: - Wiring, and the invariant that matters

    /// Driving `emit` rather than `blockedBlock` — a unit test on the block would pass just as
    /// well if nothing called it.
    @Test("the hint reaches the emitted file through the real pipeline")
    func hintIsWiredThroughEmit() {
        let emission = KitSuiteEmitter.emit(
            findings: [finding("Deque", conformances: ["Equatable"])],
            shapes: ["Deque": opaqueShape("Deque")],
            moduleName: "DequeModule",
            genericParametersByName: [
                "Deque": [TypeDecl.GenericParameter(name: "Element", constraint: nil)]
            ]
        )
        #expect(emission.blockedCarriers == 1)
        #expect(emission.source.contains("Gen<Deque<Int>>.smallIntDeque()"))
    }

    /// **The dependency invariant.** `PropertyLawCollections` may appear in commented-out
    /// text and nowhere else; a live suite that referenced it would fail to build for every
    /// reader who has not opted into the product.
    @Test("the live path never references the opt-in product")
    func livePathStaysFreeOfTheProduct() {
        let money = TypeShape(
            name: "Money", kind: .struct, inheritedTypes: ["Equatable"], hasUserGen: false,
            storedMembers: [StoredMember(name: "cents", typeName: "Int")]
        )
        let emission = KitSuiteEmitter.emit(
            findings: [
                finding("Money", conformances: ["Equatable"]),
                finding("Deque", conformances: ["Equatable"])
            ],
            shapes: ["Money": money, "Deque": opaqueShape("Deque")],
            moduleName: "M",
            genericParametersByName: [
                "Deque": [TypeDecl.GenericParameter(name: "Element", constraint: nil)]
            ]
        )
        #expect(emission.liveCarriers == 1, "Money derives")
        #expect(emission.blockedCarriers == 1, "Deque does not")
        #expect(!emission.source.contains("import PropertyLawCollections"))
        for line in emission.source.split(separator: "\n")
        where line.contains("PropertyLawCollections") || line.contains("smallIntDeque") {
            #expect(line.trimmingCharacters(in: .whitespaces).hasPrefix("//"))
        }
    }

    // MARK: - Freshness

    /// **The recipes are read off another repo, so a rename there makes this table lie.**
    /// Re-derivable only when the sibling checkout exists — the same honest limit
    /// `fixtures/effect-vocabulary` records, with `make docs-drift` as the standing detector.
    /// A CI box without the checkout skips rather than passing vacuously.
    @Test("every emitted recipe still exists in the kit")
    func recipesExistInTheKit() throws {
        let kit = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .deletingLastPathComponent()
            .appendingPathComponent("SwiftPropertyLaws/Sources/PropertyLawCollections")
        try #require(
            FileManager.default.fileExists(atPath: kit.path),
            "sibling kit checkout absent — freshness not re-derivable here"
        )
        let sources = try FileManager.default
            .contentsOfDirectory(at: kit, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined()

        for carrier in [
            "Deque<Int>", "OrderedSet<Int>", "OrderedDictionary<Int, Int>",
            "TreeSet<Int>", "TreeDictionary<Int, Int>", "BitSet", "Heap<Int>"
        ] {
            let recipe = try #require(
                KitSuiteEmitter.propertyLawCollectionsRecipe(for: carrier),
                "\(carrier) lost its recipe"
            )
            // `Gen<Deque<Int>>.smallIntDeque()` → `smallIntDeque`.
            let function = recipe
                .components(separatedBy: ">.").last?
                .replacingOccurrences(of: "()", with: "") ?? ""
            #expect(
                sources.contains("static func \(function)("),
                "the kit no longer declares `\(function)`"
            )
            #expect(
                sources.contains("Gen where Value == \(carrier)"),
                "the kit no longer extends `Gen` for `\(carrier)`"
            )
        }
        // The other direction: a type the kit HAS gained a generator for and this table has
        // not. `BitArray` is the one that would move.
        #expect(
            !sources.contains("Gen where Value == BitArray"),
            "the kit now ships a BitArray generator — add it to the table"
        )
    }
}
