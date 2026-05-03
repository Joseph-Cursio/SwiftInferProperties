import SwiftInferCore
import Testing
@testable import SwiftInferTestLifter

/// String-pattern + escape-rejection tests for `PreconditionInferrer`.
/// Split from `PreconditionInferrerTests.swift` to keep both files
/// under SwiftLint's `type_body_length` 250-line cap (same posture
/// as `LiftedTestEmitter+Generators` / `AsymmetricAssertionDetector
/// +M5Patterns` etc.).
@Suite("PreconditionInferrer — string patterns + escape rejection (M9.1)")
struct PreconditionInferrerStringTests {

    private static func shape(
        _ args: [(label: String?, kind: ParameterizedValue.Kind)]
    ) -> ConstructionShape {
        ConstructionShape(arguments: args.map {
            ConstructionShape.Argument(label: $0.label, kind: $0.kind)
        })
    }

    private static func entry(
        shape: ConstructionShape,
        rows: [[String]]
    ) -> ConstructionRecordEntry {
        ConstructionRecordEntry(
            typeName: "Doc",
            shape: shape,
            siteCount: rows.count,
            observedLiterals: rows
        )
    }

    @Test("All non-empty same-length strings → .nonEmptyString")
    func allNonEmptySameLength() {
        let entry = Self.entry(
            shape: Self.shape([(label: "code", kind: .string)]),
            rows: [["\"abc\""], ["\"xyz\""], ["\"foo\""]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .nonEmptyString)
        #expect(hints[0].suggestedGenerator.contains("verify empty-string case"))
    }

    @Test("Multi-distinct-length non-empty strings → .stringLength")
    func nonEmptyDistinctLengthRange() {
        let entry = Self.entry(
            shape: Self.shape([(label: "title", kind: .string)]),
            rows: [["\"a\""], ["\"ab\""], ["\"abc\""]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .stringLength(low: 1, high: 3))
        #expect(hints[0].suggestedGenerator == "Gen.string(of: 1...3)")
    }

    @Test("Mixed empty + non-empty distinct lengths → .stringLength with low=0")
    func mixedEmptyNonEmptyStringLength() {
        let entry = Self.entry(
            shape: Self.shape([(label: "tag", kind: .string)]),
            rows: [["\"\""], ["\"x\""], ["\"yy\""]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints[0].pattern == .stringLength(low: 0, high: 2))
    }

    @Test("All empty strings (single length 0) → no hint")
    func allEmptyStringsNoHint() {
        let entry = Self.entry(
            shape: Self.shape([(label: "tag", kind: .string)]),
            rows: [["\"\""], ["\"\""], ["\"\""]]
        )
        // Single distinct length AND all-empty → not nonEmptyString
        // (predicate fails) AND not stringLength (needs ≥ 2 distinct
        // lengths). No hint.
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    @Test("String with backslash escape kills the column")
    func backslashEscapeKillsColumn() {
        let entry = Self.entry(
            shape: Self.shape([(label: "msg", kind: .string)]),
            rows: [["\"hi\\nthere\""], ["\"hi\\nthere\""], ["\"hi\\nthere\""]]
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    @Test("Multi-line triple-quote string kills the column")
    func multiLineStringKillsColumn() {
        let entry = Self.entry(
            shape: Self.shape([(label: "doc", kind: .string)]),
            rows: [["\"\"\"abc\"\"\""], ["\"\"\"abc\"\"\""], ["\"\"\"abc\"\"\""]]
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    @Test("Raw string kills the column")
    func rawStringKillsColumn() {
        let entry = Self.entry(
            shape: Self.shape([(label: "raw", kind: .string)]),
            rows: [["#\"abc\"#"], ["#\"abc\"#"], ["#\"abc\"#"]]
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }
}
