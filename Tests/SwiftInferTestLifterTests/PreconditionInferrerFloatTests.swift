import SwiftInferCore
@testable import SwiftInferTestLifter
import Testing

/// TestLifter M15.1 — float / double pattern detection. Closes the
/// M9 plan OD #1 deferral; mirrors the integer-pattern coverage shape
/// in `PreconditionInferrerTests` plus negative cases for the
/// non-finite + unparseable literal branches.
///
/// Split out so both files stay under SwiftLint's `type_body_length`
/// 250-line cap (same posture as `PreconditionInferrerTests+Strings`).
@Suite("PreconditionInferrer — float / double patterns (M15.1)")
struct PreconditionInferrerFloatTests {

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

    // MARK: - Sign-bound patterns

    @Test("All-positive single-value column → .positiveDouble")
    func allPositiveSingleValue() {
        let entry = Self.entry(
            shape: Self.shape([(label: "ratio", kind: .float)]),
            rows: [["1.5"], ["1.5"], ["1.5"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .positiveDouble)
        #expect(hints[0].suggestedGenerator == "Gen.double(in: 0.0.nextUp...)")
    }

    @Test("All-zero single-value column → .nonNegativeDouble (positive predicate fails)")
    func allZeroSingleValue() {
        let entry = Self.entry(
            shape: Self.shape([(label: "epsilon", kind: .float)]),
            rows: [["0.0"], ["0.0"], ["0.0"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .nonNegativeDouble)
        #expect(hints[0].suggestedGenerator == "Gen.double(in: 0.0...)")
    }

    @Test("All-negative single-value column → .negativeDouble (defensive — scanner widening cover)")
    func allNegativeSingleValue() {
        // Today's M4.1 scanner can't fingerprint "-1.5" — it parses as
        // PrefixOperatorExpr and falls to .other, not .float. Test
        // exercises the parse-negative path defensively (parseDoubleLiteral
        // handles "-1.5" via Double's initializer).
        let entry = Self.entry(
            shape: Self.shape([(label: "delta", kind: .float)]),
            rows: [["-1.5"], ["-1.5"], ["-1.5"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .negativeDouble)
        #expect(hints[0].suggestedGenerator == "Gen.double(in: ...0.0.nextDown)")
    }

    // MARK: - doubleRange (most-specific per OD #4)

    @Test("Multi-distinct positive doubles → .doubleRange (range subsumes positive)")
    func positiveDistinctRange() {
        let entry = Self.entry(
            shape: Self.shape([(label: "ratio", kind: .float)]),
            rows: [["1.5"], ["2.5"], ["3.5"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .doubleRange(low: 1.5, high: 3.5))
        #expect(hints[0].suggestedGenerator == "Gen.double(in: 1.5...3.5)")
    }

    @Test("Mixed non-negative doubles (0.0 + positives) → .doubleRange")
    func nonNegativeDistinctRange() {
        let entry = Self.entry(
            shape: Self.shape([(label: "ratio", kind: .float)]),
            rows: [["0.0"], ["1.5"], ["2.5"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints[0].pattern == .doubleRange(low: 0.0, high: 2.5))
    }

    @Test("Scientific-notation literal parses via Double initializer")
    func scientificNotationParses() {
        let entry = Self.entry(
            shape: Self.shape([(label: "scale", kind: .float)]),
            rows: [["1e2"], ["1e3"], ["1e4"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .doubleRange(low: 100.0, high: 10_000.0))
    }

    @Test("Underscore-separator literals parse correctly")
    func underscoreSeparatorParses() {
        let entry = Self.entry(
            shape: Self.shape([(label: "amount", kind: .float)]),
            rows: [["1_000.5"], ["1_000.5"], ["1_000.5"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints.count == 1)
        #expect(hints[0].pattern == .positiveDouble)
    }

    // MARK: - Conservative kills

    @Test("Hex-prefixed literal kills the column (parser rejects)")
    func hexLiteralKillsColumn() {
        let entry = Self.entry(
            shape: Self.shape([(label: "magnitude", kind: .float)]),
            rows: [["0x1.0p2"], ["0x1.0p2"], ["0x1.0p2"]]
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    @Test("Garbage literal text kills the column (parser rejects)")
    func unparseableLiteralKillsColumn() {
        let entry = Self.entry(
            shape: Self.shape([(label: "ratio", kind: .float)]),
            rows: [["not-a-number"], ["1.5"], ["1.5"]]
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    @Test("Non-finite parsed value (e.g. 'inf') kills the column")
    func nonFiniteKillsColumn() {
        // Defensive cover for future scanner widening — `1e500` overflows
        // Double to +infinity even though it's lexically a float literal.
        let entry = Self.entry(
            shape: Self.shape([(label: "ratio", kind: .float)]),
            rows: [["1e500"], ["1.5"], ["1.5"]]
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    @Test("Under-threshold float column emits no hint")
    func underThresholdNoHints() {
        let entry = Self.entry(
            shape: Self.shape([(label: "ratio", kind: .float)]),
            rows: [["1.5"], ["2.5"]]
        )
        #expect(PreconditionInferrer.infer(from: entry).isEmpty)
    }

    @Test("Mixed sign-bound but single-distinct → no sign-bound hint fires")
    func mixedSignSingleDistinctNoHint() {
        // Three rows but only one distinct value that's negative — falls
        // through to .negativeDouble (this is the expected behavior;
        // verifies that the predicate isn't fooled by the leading "-").
        let entry = Self.entry(
            shape: Self.shape([(label: "delta", kind: .float)]),
            rows: [["-2.0"], ["-2.0"], ["-2.0"]]
        )
        let hints = PreconditionInferrer.infer(from: entry)
        #expect(hints[0].pattern == .negativeDouble)
    }
}
