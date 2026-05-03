import SwiftInferCore
import SwiftInferCLI
import SwiftInferTemplates
import Testing
@testable import SwiftInferTestLifter

@Suite("LiftedSuggestionPipeline — M4.3 mock-inferred fallback")
struct MockInferredFallbackPipelineTests {

    // MARK: - Fixtures

    private static let dummyOrigin = LiftedOrigin(
        testMethodName: "testFoo",
        sourceLocation: SourceLocation(file: "Tests/Foo.swift", line: 1, column: 1)
    )

    /// Build an idempotence lifted suggestion with no FunctionSummary
    /// match; recovery falls through to the annotation tier.
    private static func idempotenceLifted(
        calleeName: String,
        inputBindingName: String
    ) -> LiftedSuggestion {
        let detection = DetectedIdempotence(
            calleeName: calleeName,
            inputBindingName: inputBindingName,
            assertionLocation: SourceLocation(file: "Tests/Foo.swift", line: 5, column: 1)
        )
        return LiftedSuggestion.idempotence(from: detection, origin: dummyOrigin)
    }

    private static func docShape(siteCount: Int) -> ConstructionRecord {
        let shape = ConstructionShape(arguments: [
            ConstructionShape.Argument(label: "title", kind: .string)
        ])
        let entry = ConstructionRecordEntry(
            typeName: "Doc",
            shape: shape,
            siteCount: siteCount,
            observedLiterals: Array(repeating: ["\"x\""], count: siteCount)
        )
        return ConstructionRecord(entries: [entry])
    }

    // MARK: - Mock fallback fires

    @Test("Lifted suggestion with annotation-recovered Doc + ≥3 sites gets .inferredFromTests source")
    func mockFallbackFiresForLiftedAnnotated() {
        let lifted = Self.idempotenceLifted(calleeName: "normalize", inputBindingName: "doc")
        let annotations: [LiftedOrigin: [String: String]] = [
            Self.dummyOrigin: ["doc": "Doc"]
        ]
        let result = LiftedSuggestionPipeline.promote(
            lifted: [lifted],
            templateEngineSuggestions: [],
            summaries: [],
            typeDecls: [],
            setupAnnotationsByOrigin: annotations,
            constructionRecord: Self.docShape(siteCount: 3)
        )
        let promoted = try? #require(result.first)
        #expect(promoted?.generator.source == .inferredFromTests)
        #expect(promoted?.generator.confidence == .low)
        #expect(promoted?.mockGenerator?.typeName == "Doc")
        #expect(promoted?.mockGenerator?.siteCount == 3)
    }

    // MARK: - Mock fallback does NOT fire

    @Test("Under-threshold sites (2) leave the lifted suggestion at .notYetComputed")
    func mockFallbackNoFireForUnderThreshold() {
        let lifted = Self.idempotenceLifted(calleeName: "normalize", inputBindingName: "doc")
        let annotations: [LiftedOrigin: [String: String]] = [
            Self.dummyOrigin: ["doc": "Doc"]
        ]
        let result = LiftedSuggestionPipeline.promote(
            lifted: [lifted],
            templateEngineSuggestions: [],
            summaries: [],
            typeDecls: [],
            setupAnnotationsByOrigin: annotations,
            constructionRecord: Self.docShape(siteCount: 2)
        )
        let promoted = try? #require(result.first)
        #expect(promoted?.generator.source == .notYetComputed)
        #expect(promoted?.mockGenerator == nil)
    }

    @Test("Empty construction record leaves all suggestions untouched")
    func emptyRecordNoFallback() {
        let lifted = Self.idempotenceLifted(calleeName: "normalize", inputBindingName: "doc")
        let annotations: [LiftedOrigin: [String: String]] = [
            Self.dummyOrigin: ["doc": "Doc"]
        ]
        let result = LiftedSuggestionPipeline.promote(
            lifted: [lifted],
            templateEngineSuggestions: [],
            summaries: [],
            typeDecls: [],
            setupAnnotationsByOrigin: annotations,
            constructionRecord: ConstructionRecord(entries: [])
        )
        let promoted = try? #require(result.first)
        #expect(promoted?.generator.source == .notYetComputed)
        #expect(promoted?.mockGenerator == nil)
    }

    @Test("Type recovery fails (no annotation, no FunctionSummary) → mock can't fire")
    func noTypeRecoveryNoMock() {
        let lifted = Self.idempotenceLifted(calleeName: "normalize", inputBindingName: "doc")
        // No annotations supplied → typeName lookup misses → fallback can't fire.
        let result = LiftedSuggestionPipeline.promote(
            lifted: [lifted],
            templateEngineSuggestions: [],
            summaries: [],
            typeDecls: [],
            setupAnnotationsByOrigin: [:],
            constructionRecord: Self.docShape(siteCount: 3)
        )
        let promoted = try? #require(result.first)
        #expect(promoted?.generator.source == .notYetComputed)
        #expect(promoted?.mockGenerator == nil)
    }
}
