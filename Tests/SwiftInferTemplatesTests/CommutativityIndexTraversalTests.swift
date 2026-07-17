import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// Cycle 149 (Lever B) — the Collection index-traversal exclusion in
// `binaryOperatorTypeSymmetrySignal`. Split out of
// `CommutativityTemplateTests.swift` (cycle 150) to keep that file under
// SwiftLint's 400-line cap.
@Suite("CommutativityTemplate — Collection index-traversal exclusion (cycle 149)")
struct CommutativityIndexTraversalTests {

    @Test("distance(from:to:) is NOT a commutativity candidate (Collection index-traversal)")
    func distanceFromToExcluded() {
        // On OrderedSet (Index == Int) this is (Int, Int) -> Int by shape, but
        // `distance` is antisymmetric — a signature false positive.
        let summary = Self.summary(
            name: "distance",
            parameters: [
                Parameter(label: "from", internalName: "a", typeText: "Int", isInout: false),
                Parameter(label: "to", internalName: "b", typeText: "Int", isInout: false)
            ]
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("index(_:offsetBy:) is NOT a commutativity candidate (Collection index-traversal)")
    func indexOffsetByExcluded() {
        let summary = Self.summary(
            name: "index",
            parameters: [
                Parameter(label: nil, internalName: "i", typeText: "Int", isInout: false),
                Parameter(label: "offsetBy", internalName: "n", typeText: "Int", isInout: false)
            ]
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("a same-named method with different labels is unaffected (matched by base name + labels)")
    func sameNameDifferentLabelsStillMatches() {
        // `distance(x:y:)` — not the Collection requirement, so the index-traversal
        // exclusion (this test's subject) does NOT fire and the shape signal
        // survives. The final `suggest(...)` is now separately gated by B24 (no
        // commutative name), so assert the exclusion at the signal it controls
        // rather than at the downstream suggestion.
        let summary = Self.summary(
            name: "distance",
            parameters: [
                Parameter(label: "x", internalName: "x", typeText: "Int", isInout: false),
                Parameter(label: "y", internalName: "y", typeText: "Int", isInout: false)
            ]
        )
        #expect(summary.binaryOperatorTypeSymmetrySignal != nil)
    }

    private static func summary(name: String, parameters: [Parameter]) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }
}
