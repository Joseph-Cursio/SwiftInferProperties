import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.25.A — name-prefix-gated magnitude bump on V1.10.1's idempotence
/// direction-label counter. Direct cycle-21 finding closure: 13+ OC
/// `index(after:)` / `index(before:)` direction-op idempotence rejects
/// dominate the residual non-lifted idempotence pool at v1.24.
///
/// Behavior:
/// - Name starts with `index`/`bucket`/`word` + direction-labeled → -25 (full veto).
/// - Other direction-labeled functions → V1.10.1 -15 (preserved).
/// - No direction label → nil (preserved).
@Suite("IdempotenceTemplate — V1.25.A index-advance direction-op veto")
struct IdempotenceTemplateIndexAdvanceVetoTests {

    private func summary(
        _ name: String,
        paramLabel: String?,
        paramType: String = "Int",
        returnType: String = "Int"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: paramLabel, internalName: "x", typeText: paramType, isInout: false)],
            returnTypeText: returnType,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "OrderedSet",
            bodySignals: .empty
        )
    }

    // MARK: - Index-advance + direction label fires -25

    @Test("'index(after:)' fires -25 veto (cycle-21 case)")
    func indexAfterFiresMinus25() throws {
        let signal = IdempotenceTemplate.directionLabelCounterSignal(
            for: summary("index", paramLabel: "after")
        )
        let veto = try #require(signal)
        #expect(veto.weight == -25)
        #expect(veto.detail.contains("Index-advance direction-label"))
        #expect(veto.detail.contains("index"))
        #expect(veto.detail.contains("after"))
    }

    @Test("'index(before:)' fires -25")
    func indexBeforeFiresMinus25() {
        let signal = IdempotenceTemplate.directionLabelCounterSignal(
            for: summary("index", paramLabel: "before")
        )
        #expect(signal?.weight == -25)
    }

    @Test("'bucket(after:)' fires -25 (cycle-21 word-family case)")
    func bucketAfterFiresMinus25() {
        let signal = IdempotenceTemplate.directionLabelCounterSignal(
            for: summary("bucket", paramLabel: "after", paramType: "Bucket", returnType: "Bucket")
        )
        #expect(signal?.weight == -25)
    }

    @Test("'word(after:)' fires -25")
    func wordAfterFiresMinus25() {
        let signal = IdempotenceTemplate.directionLabelCounterSignal(
            for: summary("word", paramLabel: "after")
        )
        #expect(signal?.weight == -25)
    }

    // MARK: - Non-index-advance direction labels preserve V1.10.1 -15

    @Test("Non-index-advance direction-labeled function preserves V1.10.1 -15")
    func nonIndexAdvancePreservesMinus15() throws {
        // 'advance' is a direction-label adjacent verb but doesn't have
        // the index/bucket/word prefix — preserved at V1.10.1 -15.
        let signal = IdempotenceTemplate.directionLabelCounterSignal(
            for: summary("seek", paramLabel: "after")
        )
        let counter = try #require(signal)
        #expect(counter.weight == -15)
        // Detail string format preserved exactly (V1.10.1 wording).
        #expect(counter.detail.contains("Direction-label argument"))
    }

    @Test("'startIndex(next:)' preserves -15 — name doesn't start with index/bucket/word")
    func startIndexPreservesMinus15() {
        let signal = IdempotenceTemplate.directionLabelCounterSignal(
            for: summary("startIndex", paramLabel: "next")
        )
        #expect(signal?.weight == -15)
    }

    // MARK: - No direction label = nil

    @Test("No direction label returns nil (preserved from V1.10.1)")
    func nilLabelReturnsNil() {
        let signal = IdempotenceTemplate.directionLabelCounterSignal(
            for: summary("index", paramLabel: nil)
        )
        #expect(signal == nil)
    }

    @Test("Non-direction label (e.g., 'forScale') returns nil")
    func nonDirectionLabelReturnsNil() {
        let signal = IdempotenceTemplate.directionLabelCounterSignal(
            for: summary("index", paramLabel: "forScale")
        )
        #expect(signal == nil)
    }

    // MARK: - End-to-end suggest()

    @Test("End-to-end: 'index(after:)' idempotence is suppressed at v1.25.A")
    func endToEndIndexAfterSuppressed() {
        let suggestion = IdempotenceTemplate.suggest(for: summary("index", paramLabel: "after"))
        // 30 typeSymmetry - 25 V1.25.A = +5 → Suppressed.
        #expect(suggestion == nil, "V1.25.A should suppress index-advance idempotence")
    }
}
