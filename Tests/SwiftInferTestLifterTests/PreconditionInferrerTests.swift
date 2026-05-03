import SwiftInferCore
import Testing
@testable import SwiftInferTestLifter

@Suite("PreconditionInferrer — pure-function pattern detection (M9.1)")
struct PreconditionInferrerTests {

    // MARK: - Helpers

    private static func shape(
        _ args: [(label: String?, kind: ParameterizedValue.Kind)]
    ) -> ConstructionShape {
        ConstructionShape(arguments: args.map {
            ConstructionShape.Argument(label: $0.label, kind: $0.kind)
        })
    }

    /// Build a `ConstructionRecordEntry` with the supplied per-site
    /// literal rows. Each row's length must match the shape's
    /// argument count.
    private static func entry(
        typeName: String = "Doc",
        shape: ConstructionShape,
        rows: [[String]]
    ) -> ConstructionRecordEntry {
        ConstructionRecordEntry(
            typeName: typeName,
            shape: shape,
            siteCount: rows.count,
            observedLiterals: rows
        )
    }

    // MARK: - Threshold

    @Test("Under-threshold entries (<3 sites) emit no hints")
    func underThresholdNoHints() {
        let entry = Self.entry(
            shape: Self.shape([(label: "value", kind: .integer)]),
            rows: [["1"], ["2"]]
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    @Test("Empty entry (0 sites) emits no hints")
    func emptyEntryNoHints() {
        let entry = Self.entry(
            shape: Self.shape([(label: "value", kind: .integer)]),
            rows: []
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    @Test("Empty argument shape emits no hints regardless of site count")
    func emptyShapeNoHints() {
        let entry = Self.entry(
            shape: Self.shape([]),
            rows: [[], [], []]
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    // MARK: - Integer patterns

    @Test("All-positive single-value column → .positiveInt")
    func allPositiveSingleValue() {
        let entry = Self.entry(
            shape: Self.shape([(label: "count", kind: .integer)]),
            rows: [["5"], ["5"], ["5"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].position == 0)
        #expect(hints[0].argumentLabel == "count")
        #expect(hints[0].pattern == .positiveInt)
        #expect(hints[0].siteCount == 3)
        #expect(hints[0].suggestedGenerator == "Gen.int(in: 1...)")
    }

    @Test("Multi-distinct positive ints → .intRange (most-specific wins per OD #4)")
    func positiveDistinctRange() {
        let entry = Self.entry(
            shape: Self.shape([(label: "count", kind: .integer)]),
            rows: [["1"], ["2"], ["3"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .intRange(low: 1, high: 3))
        #expect(hints[0].suggestedGenerator == "Gen.int(in: 1...3)")
    }

    @Test("All-zero single-value column → .nonNegativeInt (positive predicate fails)")
    func allZeroSingleValue() {
        let entry = Self.entry(
            shape: Self.shape([(label: "depth", kind: .integer)]),
            rows: [["0"], ["0"], ["0"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .nonNegativeInt)
        #expect(hints[0].suggestedGenerator == "Gen.int(in: 0...)")
    }

    @Test("Mixed non-negative ints → .intRange (range subsumes nonNegative)")
    func nonNegativeDistinctRange() {
        let entry = Self.entry(
            shape: Self.shape([(label: "depth", kind: .integer)]),
            rows: [["0"], ["1"], ["2"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints[0].pattern == .intRange(low: 0, high: 2))
    }

    @Test("All-negative single-value column → .negativeInt (defensive — scanner widening cover)")
    func allNegativeSingleValue() {
        // The current M4.1 scanner doesn't fingerprint PrefixOperatorExpr
        // negative literals — this column wouldn't reach the inferrer
        // through the live pipeline today. Test exercises the parse-
        // negative path defensively (parseIntLiteral handles "-5" via
        // Swift's Int initializer).
        let entry = Self.entry(
            shape: Self.shape([(label: "delta", kind: .integer)]),
            rows: [["-5"], ["-5"], ["-5"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .negativeInt)
        #expect(hints[0].suggestedGenerator == "Gen.int(in: ...(-1))")
    }

    @Test("Underscore-separator literals parse correctly")
    func underscoreSeparatorParses() {
        let entry = Self.entry(
            shape: Self.shape([(label: "size", kind: .integer)]),
            rows: [["1_000"], ["1_000"], ["1_000"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .positiveInt)
    }

    @Test("Hex-prefixed literal kills the column (conservative parse)")
    func hexLiteralKillsColumn() {
        let entry = Self.entry(
            shape: Self.shape([(label: "mask", kind: .integer)]),
            rows: [["0xFF"], ["0xFF"], ["0xFF"]]
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    // String-pattern tests live in PreconditionInferrerTests+Strings.swift.

    // MARK: - Boolean patterns

    @Test("All-true bool column → .constantBool(true)")
    func allTrueBool() {
        let entry = Self.entry(
            shape: Self.shape([(label: "enabled", kind: .boolean)]),
            rows: [["true"], ["true"], ["true"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .constantBool(value: true))
        #expect(hints[0].suggestedGenerator.contains("opposite case may be untested"))
    }

    @Test("All-false bool column → .constantBool(false)")
    func allFalseBool() {
        let entry = Self.entry(
            shape: Self.shape([(label: "disabled", kind: .boolean)]),
            rows: [["false"], ["false"], ["false"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints[0].pattern == .constantBool(value: false))
    }

    @Test("Mixed bool column → no hint (one outlier kills)")
    func mixedBoolOutlierKills() {
        let entry = Self.entry(
            shape: Self.shape([(label: "flag", kind: .boolean)]),
            rows: [["true"], ["true"], ["false"]]
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    // MARK: - Float (deferred per OD #1)

    @Test("Float column emits no hint (OD #1: Int-only for v1.0)")
    func floatColumnDeferred() {
        let entry = Self.entry(
            shape: Self.shape([(label: "ratio", kind: .float)]),
            rows: [["1.5"], ["2.5"], ["3.5"]]
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    // MARK: - Multi-position fan-out

    @Test("Multi-arg shape produces one hint per matching position")
    func multiArgFanOut() {
        // Shape canonical sort: count(integer) < title(string) by label.
        let entry = Self.entry(
            shape: Self.shape([
                (label: "count", kind: .integer),
                (label: "title", kind: .string)
            ]),
            rows: [
                ["1", "\"a\""],
                ["2", "\"bb\""],
                ["3", "\"ccc\""]
            ]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 2)
        // Position 0 — int range
        let intHint = try? #require(hints.first { $0.argumentLabel == "count" })
        #expect(intHint?.pattern == .intRange(low: 1, high: 3))
        // Position 1 — string length range
        let strHint = try? #require(hints.first { $0.argumentLabel == "title" })
        #expect(strHint?.pattern == .stringLength(low: 1, high: 3))
    }

    @Test("Multi-arg shape with one matching + one non-matching emits only the match")
    func multiArgPartialMatch() {
        let entry = Self.entry(
            shape: Self.shape([
                (label: "count", kind: .integer),
                (label: "flag", kind: .boolean)
            ]),
            rows: [
                ["1", "true"],
                ["2", "false"],  // mixed bool — outlier
                ["3", "true"]
            ]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].argumentLabel == "count")
    }

    // MARK: - Nil-label positional arguments

    @Test("Nil-label positional argument carries through to hint")
    func nilLabelPositional() {
        let entry = Self.entry(
            shape: Self.shape([(label: nil, kind: .integer)]),
            rows: [["1"], ["2"], ["3"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].argumentLabel == nil)
        #expect(hints[0].pattern == .intRange(low: 1, high: 3))
    }
}
