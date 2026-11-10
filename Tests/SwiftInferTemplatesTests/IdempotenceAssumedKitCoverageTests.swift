import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// MARK: - Idempotence

@Suite("AssumedKitCoverage — idempotence (V1.5.2)")
struct IdempotenceAssumedKitCoverageTests {

    @Test("Idempotence on : SetAlgebra type vetoes (covers setIntersectionIdempotent)")
    func setAlgebraVetoesIdempotence() {
        let summary = makeUnaryOp(name: "intersect", typeText: "MySet")
        let result = IdempotenceTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("MySet", conformances: ["SetAlgebra"])
        )
        #expect(result == nil, "SetAlgebra coverage should suppress idempotence")
    }

    @Test("Idempotence on : Semilattice type vetoes (covers semilatticeIdempotence)")
    func semilatticeVetoesIdempotence() {
        let summary = makeUnaryOp(name: "merge", typeText: "Lattice")
        let result = IdempotenceTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("Lattice", conformances: ["Semilattice"])
        )
        #expect(result == nil)
    }

    @Test("Idempotence on type with no relevant conformance still surfaces")
    func customTypeWithoutConformanceSurfaces() throws {
        let summary = makeUnaryOp(name: "normalize", typeText: "Doc")
        let suggestion = try #require(IdempotenceTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("Doc", conformances: ["Hashable", "Sendable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("Idempotence on : Numeric is NOT vetoed (Numeric covers no idempotence law)")
    func numericDoesNotVetoIdempotence() throws {
        let summary = makeUnaryOp(name: "normalize", typeText: "Int")
        let suggestion = try #require(IdempotenceTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("Int", conformances: ["Numeric"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("Idempotence falls through cleanly with empty inheritedTypesByName")
    func emptyIndexIsBackwardsCompat() throws {
        let summary = makeUnaryOp(name: "normalize", typeText: "String")
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }
}
