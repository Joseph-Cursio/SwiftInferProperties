import Testing
@testable import SwiftInferCore

@Suite("PreconditionHint — data model (M9.0)")
struct PreconditionHintTests {

    @Test
    func equatableConformanceMatchesByValue() {
        let hint1 = PreconditionHint(
            position: 0,
            argumentLabel: "value",
            pattern: .positiveInt,
            siteCount: 5,
            suggestedGenerator: "Gen.int(in: 1...)"
        )
        let hint2 = PreconditionHint(
            position: 0,
            argumentLabel: "value",
            pattern: .positiveInt,
            siteCount: 5,
            suggestedGenerator: "Gen.int(in: 1...)"
        )
        let hint3 = PreconditionHint(
            position: 1,
            argumentLabel: "value",
            pattern: .positiveInt,
            siteCount: 5,
            suggestedGenerator: "Gen.int(in: 1...)"
        )
        #expect(hint1 == hint2)
        #expect(hint1 != hint3)
    }

    @Test
    func patternEquatableDistinguishesCases() {
        #expect(PreconditionPattern.positiveInt == PreconditionPattern.positiveInt)
        #expect(PreconditionPattern.positiveInt != PreconditionPattern.nonNegativeInt)
        #expect(PreconditionPattern.intRange(low: 0, high: 10) == .intRange(low: 0, high: 10))
        #expect(PreconditionPattern.intRange(low: 0, high: 10) != .intRange(low: 0, high: 11))
        #expect(PreconditionPattern.stringLength(low: 1, high: 8) != .nonEmptyString)
        #expect(PreconditionPattern.constantBool(value: true) != .constantBool(value: false))
    }

    @Test
    func mockGeneratorPreconditionHintsDefaultsToEmpty() {
        let mock = MockGenerator(
            typeName: "Doc",
            argumentSpec: [],
            siteCount: 5
        )
        #expect(mock.preconditionHints.isEmpty)
    }

    @Test
    func mockGeneratorAcceptsExplicitPreconditionHints() {
        let hint = PreconditionHint(
            position: 0,
            argumentLabel: "count",
            pattern: .positiveInt,
            siteCount: 5,
            suggestedGenerator: "Gen.int(in: 1...)"
        )
        let mock = MockGenerator(
            typeName: "Doc",
            argumentSpec: [],
            siteCount: 5,
            preconditionHints: [hint]
        )
        #expect(mock.preconditionHints == [hint])
    }

    @Test
    func mockGeneratorEquatableComparesPreconditionHints() {
        let hint = PreconditionHint(
            position: 0,
            argumentLabel: nil,
            pattern: .nonEmptyString,
            siteCount: 3,
            suggestedGenerator: "Gen.string()"
        )
        let withHint = MockGenerator(
            typeName: "Doc", argumentSpec: [], siteCount: 3, preconditionHints: [hint]
        )
        let withoutHint = MockGenerator(typeName: "Doc", argumentSpec: [], siteCount: 3)
        #expect(withHint != withoutHint)
        let alsoWithHint = MockGenerator(
            typeName: "Doc", argumentSpec: [], siteCount: 3, preconditionHints: [hint]
        )
        #expect(withHint == alsoWithHint)
    }
}
