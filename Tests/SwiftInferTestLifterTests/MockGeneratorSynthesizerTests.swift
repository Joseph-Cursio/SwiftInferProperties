import SwiftInferCore
import Testing
@testable import SwiftInferTestLifter

@Suite("MockGeneratorSynthesizer (TestLifter M4.3)")
struct MockGeneratorSynthesizerTests {

    // MARK: - Helpers

    private static func entry(
        typeName: String,
        shape: ConstructionShape,
        siteCount: Int
    ) -> ConstructionRecordEntry {
        ConstructionRecordEntry(
            typeName: typeName,
            shape: shape,
            siteCount: siteCount,
            observedLiterals: Array(
                repeating: shape.arguments.map { _ in "\"\"" },
                count: siteCount
            )
        )
    }

    private static func shape(_ args: [(label: String?, kind: ParameterizedValue.Kind)]) -> ConstructionShape {
        ConstructionShape(arguments: args.map {
            ConstructionShape.Argument(label: $0.label, kind: $0.kind)
        })
    }

    // MARK: - § 13 threshold rule

    @Test("≥3-site single-shape input synthesizes a MockGenerator")
    func threeSiteSingleShapeSynthesizes() {
        let docShape = Self.shape([(label: "title", kind: .string), (label: "count", kind: .integer)])
        let record = ConstructionRecord(entries: [
            Self.entry(typeName: "Doc", shape: docShape, siteCount: 3)
        ])
        let synthesized = MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record)
        let mock = try? #require(synthesized)
        #expect(mock?.typeName == "Doc")
        #expect(mock?.siteCount == 3)
        #expect(mock?.argumentSpec.count == 2)
        // Args are in canonical (label-then-kind) sort order: count < title.
        #expect(mock?.argumentSpec[0].label == "count")
        #expect(mock?.argumentSpec[0].swiftTypeName == "Int")
        #expect(mock?.argumentSpec[1].label == "title")
        #expect(mock?.argumentSpec[1].swiftTypeName == "String")
    }

    @Test("2-site input returns nil — under § 13 ≥3-site threshold")
    func twoSiteUnderThreshold() {
        let docShape = Self.shape([(label: "title", kind: .string)])
        let record = ConstructionRecord(entries: [
            Self.entry(typeName: "Doc", shape: docShape, siteCount: 2)
        ])
        let synthesized = MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record)
        #expect(synthesized == nil)
    }

    @Test("1-site input returns nil")
    func oneSiteUnderThreshold() {
        let docShape = Self.shape([])
        let record = ConstructionRecord(entries: [
            Self.entry(typeName: "Doc", shape: docShape, siteCount: 1)
        ])
        let synthesized = MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record)
        #expect(synthesized == nil)
    }

    // MARK: - Multi-shape ambiguity rule

    @Test("≥3-site multi-shape input returns nil — ambiguous corpus")
    func multiShapeAmbiguityReturnsNil() {
        let shape1 = Self.shape([(label: "title", kind: .string)])
        let shape2 = Self.shape([(label: "title", kind: .string), (label: "author", kind: .string)])
        let record = ConstructionRecord(entries: [
            Self.entry(typeName: "Doc", shape: shape1, siteCount: 3),
            Self.entry(typeName: "Doc", shape: shape2, siteCount: 3)
        ])
        // Even though each individual shape clears the threshold, the
        // type has TWO shapes → ambiguous → nil per OD #3 default.
        let synthesized = MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record)
        #expect(synthesized == nil)
    }

    // MARK: - Type lookup miss

    @Test("Type with no record entries returns nil")
    func unknownTypeReturnsNil() {
        let record = ConstructionRecord(entries: [])
        let synthesized = MockGeneratorSynthesizer.synthesize(typeName: "UnknownType", record: record)
        #expect(synthesized == nil)
    }

    // MARK: - Empty constructor

    @Test("Empty constructor `Doc()` × 3 sites synthesizes a MockGenerator with empty argument spec")
    func emptyConstructorSynthesizes() {
        let emptyShape = Self.shape([])
        let record = ConstructionRecord(entries: [
            Self.entry(typeName: "Doc", shape: emptyShape, siteCount: 3)
        ])
        let synthesized = MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record)
        let mock = try? #require(synthesized)
        #expect(mock?.argumentSpec.isEmpty == true)
        #expect(mock?.siteCount == 3)
    }

    // MARK: - Kind translation

    @Test("All four ParameterizedValue.Kind cases map to correct Swift type names")
    func kindTranslationCoverage() {
        let allKindsShape = Self.shape([
            (label: "i", kind: .integer),
            (label: "s", kind: .string),
            (label: "b", kind: .boolean),
            (label: "f", kind: .float)
        ])
        let record = ConstructionRecord(entries: [
            Self.entry(typeName: "AllKinds", shape: allKindsShape, siteCount: 3)
        ])
        let synthesized = MockGeneratorSynthesizer.synthesize(typeName: "AllKinds", record: record)
        let mock = try? #require(synthesized)
        let typeNames = Set(mock?.argumentSpec.map(\.swiftTypeName) ?? [])
        #expect(typeNames == ["Int", "String", "Bool", "Double"])
    }

    // MARK: - Observed-literals row alignment

    @Test("Observed literals are stored in the canonical-sorted argument order")
    func observedLiteralsAlignWithSortedArguments() {
        let docShape = Self.shape([(label: "title", kind: .string), (label: "count", kind: .integer)])
        // Canonical sort: count < title, so position 0 = count, position 1 = title.
        let entry = ConstructionRecordEntry(
            typeName: "Doc",
            shape: docShape,
            siteCount: 3,
            observedLiterals: [
                ["3", "\"x\""],
                ["5", "\"y\""],
                ["7", "\"z\""]
            ]
        )
        let record = ConstructionRecord(entries: [entry])
        let synthesized = MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record)
        let mock = try? #require(synthesized)
        // Per-argument observedLiterals reflect the per-site values at
        // that argument's position.
        #expect(mock?.argumentSpec[0].label == "count")
        #expect(mock?.argumentSpec[0].observedLiterals == ["3", "5", "7"])
        #expect(mock?.argumentSpec[1].label == "title")
        #expect(mock?.argumentSpec[1].observedLiterals == ["\"x\"", "\"y\"", "\"z\""])
    }

    // MARK: - M9.2 — preconditionHints population

    @Test("Synthesize populates preconditionHints from observed-literal patterns")
    func synthesizePopulatesPreconditionHints() {
        let docShape = Self.shape([(label: "count", kind: .integer)])
        // Canonical position 0 = count. All observed values positive
        // ints with ≥ 2 distinct → .intRange (most-specific wins per OD #4).
        let entry = ConstructionRecordEntry(
            typeName: "Doc",
            shape: docShape,
            siteCount: 5,
            observedLiterals: [["1"], ["2"], ["3"], ["4"], ["5"]]
        )
        let record = ConstructionRecord(entries: [entry])
        let synthesized = MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record)
        let mock = try? #require(synthesized)
        #expect(mock?.preconditionHints.count == 1)
        #expect(mock?.preconditionHints[0].pattern == .intRange(low: 1, high: 5))
        #expect(mock?.preconditionHints[0].argumentLabel == "count")
        #expect(mock?.preconditionHints[0].siteCount == 5)
    }

    @Test("Synthesize emits empty preconditionHints when no pattern matches")
    func synthesizePopulatesNoHintsWhenNoPattern() {
        let docShape = Self.shape([(label: "flag", kind: .boolean)])
        // Mixed bool — no constantBool hint can fire (one outlier kills).
        let entry = ConstructionRecordEntry(
            typeName: "Doc",
            shape: docShape,
            siteCount: 4,
            observedLiterals: [["true"], ["false"], ["true"], ["false"]]
        )
        let record = ConstructionRecord(entries: [entry])
        let synthesized = MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record)
        let mock = try? #require(synthesized)
        #expect(mock?.preconditionHints.isEmpty == true)
    }
}
