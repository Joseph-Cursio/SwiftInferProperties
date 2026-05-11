import Testing
import Foundation
import SwiftInferCore
@testable import SwiftInferCLI

/// V1.35.A — `RefactorClusterAnalyzer` classification + ordering tests.
@Suite("RefactorClusterAnalyzer — V1.35.A classification + ordering")
struct RefactorClusterAnalyzerTests {

    // MARK: - Fixture helpers

    private func entry(
        identityHex: String,
        templateName: String,
        typeName: String?,
        score: Int = 30,
        funcName: String = "f()"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: identityHex,
            templateName: templateName,
            typeName: typeName,
            score: score,
            tier: "Possible",
            primaryFunctionName: funcName,
            location: "/x.swift:1",
            decision: nil,
            decisionAt: nil,
            firstSeenAt: "2026-05-11T00:00:00Z",
            lastSeenAt: "2026-05-11T00:00:00Z"
        )
    }

    // MARK: - classify(perTemplateCounts:total:)

    @Test("V1.35.A — algebraicStructure: 2 distinct algebraic templates")
    func classifyAlgebraicStructureTwoTemplates() {
        let shape = RefactorClusterAnalyzer.classify(
            perTemplateCounts: ["commutativity": 1, "associativity": 1],
            total: 2
        )
        #expect(shape == .algebraicStructure)
    }

    @Test("V1.35.A — algebraicStructure: all three (commutativity + associativity + identity-element)")
    func classifyAlgebraicStructureAllThree() {
        let shape = RefactorClusterAnalyzer.classify(
            perTemplateCounts: ["commutativity": 2, "associativity": 2, "identity-element": 1],
            total: 5
        )
        #expect(shape == .algebraicStructure)
    }

    @Test("V1.35.A — algebraicStructure with only 1 algebraic template does NOT classify as algebraic")
    func classifyAlgebraicStructureSingleTemplateDoesNotMatch() {
        let shape = RefactorClusterAnalyzer.classify(
            perTemplateCounts: ["commutativity": 5],   // 5 commutativity, no associativity
            total: 5
        )
        // Should fall through to generalCluster since total ≥ 4 but
        // algebraicStructure requires 2+ distinct templates.
        #expect(shape == .generalCluster)
    }

    @Test("V1.35.A — idempotenceCluster: ≥3 idempotence suggestions")
    func classifyIdempotenceCluster() {
        let shape = RefactorClusterAnalyzer.classify(
            perTemplateCounts: ["idempotence": 3],
            total: 3
        )
        #expect(shape == .idempotenceCluster)
    }

    @Test("V1.35.A — idempotence count = 2 does NOT cluster (threshold edge)")
    func classifyIdempotenceBelowThreshold() {
        let shape = RefactorClusterAnalyzer.classify(
            perTemplateCounts: ["idempotence": 2],
            total: 2
        )
        #expect(shape == nil)
    }

    @Test("V1.35.A — dualStyleCluster: ≥3 dual-style-consistency suggestions")
    func classifyDualStyleCluster() {
        let shape = RefactorClusterAnalyzer.classify(
            perTemplateCounts: ["dual-style-consistency": 3],
            total: 3
        )
        #expect(shape == .dualStyleCluster)
    }

    @Test("V1.35.A — roundTripCluster: ≥3 round-trip suggestions")
    func classifyRoundTripCluster() {
        let shape = RefactorClusterAnalyzer.classify(
            perTemplateCounts: ["round-trip": 3],
            total: 3
        )
        #expect(shape == .roundTripCluster)
    }

    @Test("V1.35.A — generalCluster: ≥4 total but no named pattern")
    func classifyGeneralCluster() {
        let shape = RefactorClusterAnalyzer.classify(
            perTemplateCounts: ["monotonicity": 2, "invariant-preservation": 2],
            total: 4
        )
        #expect(shape == .generalCluster)
    }

    @Test("V1.35.A — total < 4 with no named pattern is not a cluster")
    func classifyBelowGeneralThreshold() {
        let shape = RefactorClusterAnalyzer.classify(
            perTemplateCounts: ["monotonicity": 2, "invariant-preservation": 1],
            total: 3
        )
        #expect(shape == nil)
    }

    // MARK: - Priority order

    @Test("V1.35.A — algebraicStructure wins over generalCluster (priority)")
    func priorityAlgebraicBeatsGeneral() {
        // 5 total, 2 distinct algebraic templates AND total ≥ 4.
        let shape = RefactorClusterAnalyzer.classify(
            perTemplateCounts: ["commutativity": 1, "associativity": 1, "monotonicity": 3],
            total: 5
        )
        #expect(shape == .algebraicStructure)
    }

    @Test("V1.35.A — idempotenceCluster wins over generalCluster (priority)")
    func priorityIdempotenceBeatsGeneral() {
        let shape = RefactorClusterAnalyzer.classify(
            perTemplateCounts: ["idempotence": 3, "monotonicity": 2],
            total: 5
        )
        #expect(shape == .idempotenceCluster)
    }

    @Test("V1.35.A — algebraicStructure wins over idempotenceCluster (priority)")
    func priorityAlgebraicBeatsIdempotence() {
        let shape = RefactorClusterAnalyzer.classify(
            perTemplateCounts: ["commutativity": 1, "associativity": 1, "idempotence": 3],
            total: 5
        )
        #expect(shape == .algebraicStructure)
    }

    // MARK: - analyze(...) end-to-end

    @Test("V1.35.A — analyze filters out nil-typeName entries")
    func analyzeFiltersNilTypeName() {
        let entries = [
            entry(identityHex: "0xA", templateName: "monotonicity", typeName: nil),
            entry(identityHex: "0xB", templateName: "monotonicity", typeName: nil),
            entry(identityHex: "0xC", templateName: "monotonicity", typeName: nil),
            entry(identityHex: "0xD", templateName: "monotonicity", typeName: nil)
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
            entry(identityHex: "0x20", templateName: "monotonicity", typeName: "Foo")
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
            entry(identityHex: "0x04", templateName: "idempotence", typeName: "Foo", score: 70, funcName: "highScore()"),
            entry(identityHex: "0x05", templateName: "idempotence", typeName: "Foo", score: 25, funcName: "low2Score()"),
            entry(identityHex: "0x06", templateName: "idempotence", typeName: "Foo", score: 60, funcName: "above5()"),
            entry(identityHex: "0x07", templateName: "idempotence", typeName: "Foo", score: 20, funcName: "alsoBelow()")
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
