import SwiftInferCore
import Testing

@testable import SwiftInferCLI

@Suite("V1.51.B — DualStyleConsistencyPairResolver curated expansion")
struct V151DualStyleExpansionTests {

    private static func entry(primary: String, carrier: String = "OrderedSet") -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xABCD",
            templateName: "dual-style-consistency",
            score: 30,
            tier: "Possible",
            primaryFunctionName: primary,
            location: "/x.swift:1",
            firstSeenAt: "2026-05-12T00:00:00Z",
            lastSeenAt: "2026-05-12T00:00:00Z",
            typeName: carrier
        )
    }

    // V1.61.A — cycle-27 picks capture the **mutating** name as
    // primaryFunctionName (e.g. `formUnion(_:)`); the resolver now
    // looks up by either field and returns the correct Swift
    // SetAlgebra pair: `intersection` (non-mut) ↔ `formIntersection`
    // (mut), etc.

    @Test("V1.61.A: formIntersection lookup returns intersection / formIntersection pair")
    func formIntersection() throws {
        let result = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "formIntersection(_:)")
        )
        #expect(result.nonMutCall == "OrderedSet.intersection")
        #expect(result.mutMethodName == "formIntersection")
    }

    @Test("V1.61.A: formUnion lookup returns union / formUnion pair")
    func formUnion() throws {
        let result = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "formUnion(_:)")
        )
        #expect(result.nonMutCall == "OrderedSet.union")
        #expect(result.mutMethodName == "formUnion")
    }

    @Test("V1.61.A: formSymmetricDifference lookup returns symmetricDifference / formSymmetricDifference")
    func formSymmetricDifference() throws {
        let result = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "formSymmetricDifference(_:)")
        )
        #expect(result.nonMutCall == "OrderedSet.symmetricDifference")
        #expect(result.mutMethodName == "formSymmetricDifference")
    }

    @Test("V1.61.A: subtract lookup returns subtracting / subtract pair")
    func subtract() throws {
        let result = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "subtract(_:)")
        )
        #expect(result.nonMutCall == "OrderedSet.subtracting")
        #expect(result.mutMethodName == "subtract")
    }

    @Test("V1.61.A: merging lookup returns merging / merge")
    func mergingFamily() throws {
        let mergingPair = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "merging(_:uniquingKeysWith:)", carrier: "OrderedDictionary")
        )
        #expect(mergingPair.nonMutCall == "OrderedDictionary.merging")
        #expect(mergingPair.mutMethodName == "merge")
    }

    @Test("v1.48 initial pairs still resolve (regression guard)")
    func v1_48InitialPairsStillResolve() throws {
        let sortPair = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "sorted()", carrier: "Array")
        )
        #expect(sortPair.nonMutCall == "Array.sorted")
        #expect(sortPair.mutMethodName == "sort")
    }

    @Test("V1.61.A: curated table has 8 entries (3 v1.48 + 4 SetAlgebra + 1 merge)")
    func curatedTableSize() {
        // V1.61.A reduced from V1.51.B's 9 entries to 8: the old
        // `merge(_:uniquingKeysWith:) ↔ merge` self-pair was redundant
        // with `merging ↔ merge`; the SetAlgebra pairs corrected to
        // 4 entries (union/intersection/symmetricDifference/subtracting).
        #expect(DualStyleConsistencyPairResolver.curated.count == 8)
    }
}
