@testable import SwiftInferCLI
import Testing

extension RefactorClusterAnalyzerTests {

    // MARK: - analyze(...) end-to-end

    @Test("V1.35.A — analyze filters out nil-typeName entries")
    func analyzeFiltersNilTypeName() {
        let entries = [
            entry(identityHex: "0xA", templateName: "monotonicity", typeName: nil),
            entry(identityHex: "0xB", templateName: "monotonicity", typeName: nil),
            entry(identityHex: "0xC", templateName: "monotonicity", typeName: nil),
            entry(identityHex: "0xD", templateName: "monotonicity", typeName: nil),
        ]
        let clusters = RefactorClusterAnalyzer.analyze(entries)
        #expect(clusters.isEmpty, "nil typeName entries should not cluster")
    }

    @Test("V1.35.A — analyze groups by typeName + classifies + sorts by size desc")
    func analyzeGroupsClassifiesSorts() {
        let entries = [
            // OrderedSet: 5 idempotence → idempotenceCluster, size 5
            entry(identityHex: "0x01", templateName: "idempotence", typeName: "OrderedSet"),
            entry(identityHex: "0x02", templateName: "idempotence", typeName: "OrderedSet"),
            entry(identityHex: "0x03", templateName: "idempotence", typeName: "OrderedSet"),
            entry(identityHex: "0x04", templateName: "idempotence", typeName: "OrderedSet"),
            entry(identityHex: "0x05", templateName: "idempotence", typeName: "OrderedSet"),
            // Complex: 6 algebraic-structure → algebraicStructure, size 6
            entry(identityHex: "0x10", templateName: "commutativity", typeName: "Complex"),
            entry(identityHex: "0x11", templateName: "commutativity", typeName: "Complex"),
            entry(identityHex: "0x12", templateName: "commutativity", typeName: "Complex"),
            entry(identityHex: "0x13", templateName: "associativity", typeName: "Complex"),
            entry(identityHex: "0x14", templateName: "associativity", typeName: "Complex"),
            entry(identityHex: "0x15", templateName: "associativity", typeName: "Complex"),
            // Below-threshold (no cluster): Foo with 1 monotonicity
            entry(identityHex: "0x20", templateName: "monotonicity", typeName: "Foo"),
        ]
        let clusters = RefactorClusterAnalyzer.analyze(entries)
        #expect(clusters.count == 2, "Foo (1 entry) should not surface")
        // Complex (6) before OrderedSet (5)
        #expect(clusters[0].typeName == "Complex")
        #expect(clusters[0].totalSuggestionCount == 6)
        #expect(clusters[0].shape == .algebraicStructure)
        #expect(clusters[1].typeName == "OrderedSet")
        #expect(clusters[1].totalSuggestionCount == 5)
        #expect(clusters[1].shape == .idempotenceCluster)
    }

    @Test("V1.35.A — analyze picks up to 5 representative functions in score-desc order")
    func analyzeRepresentativesUpToFive() {
        let entries = [
            entry(identityHex: "0x01", templateName: "idempotence", typeName: "Foo", score: 30, funcName: "lowScore()"),
            entry(identityHex: "0x02", templateName: "idempotence", typeName: "Foo", score: 85, funcName: "topScore()"),
            entry(identityHex: "0x03", templateName: "idempotence", typeName: "Foo", score: 45, funcName: "midScore()"),
            entry(
                identityHex: "0x04", templateName: "idempotence", typeName: "Foo",
                score: 70, funcName: "highScore()"
            ),
            entry(
                identityHex: "0x05", templateName: "idempotence", typeName: "Foo",
                score: 25, funcName: "low2Score()"
            ),
            entry(identityHex: "0x06", templateName: "idempotence", typeName: "Foo", score: 60, funcName: "above5()"),
            entry(
                identityHex: "0x07", templateName: "idempotence", typeName: "Foo",
                score: 20, funcName: "alsoBelow()"
            ),
        ]
        let clusters = RefactorClusterAnalyzer.analyze(entries)
        #expect(clusters.count == 1)
        let representatives = clusters[0].representativeFunctions
        #expect(representatives.count == 5, "should cap at 5")
        // Score-desc order: 85, 70, 60, 45, 30
        #expect(representatives == [
            "topScore()", "highScore()", "above5()", "midScore()", "lowScore()"
        ])
    }
}
