import Testing
@testable import SwiftInferTestLifter

/// TestLifter M7.1 acceptance — `MockGeneratorSynthesizer` returns
/// nil when any observed literal in any argument position matches a
/// non-deterministic API call (`Date()`, `UUID()`, `Random.next()`,
/// etc.). Belt-and-suspenders against future scanner widening that
/// admits function-call arguments — today the M4.1
/// `SetupRegionConstructionScanner` already skips those sites at
/// scan time (literal-kind check returns nil for non-literals),
/// but M7.1 pins the explicit suppression at synthesis time.
@Suite("MockGeneratorSynthesizer — non-determinism suppression (M7.1)")
struct MockNonDeterminismSuppressionTests {

    @Test("Date() in observedLiterals suppresses synthesis")
    func dateLiteralSuppresses() {
        let entry = makeEntry(
            typeName: "Doc",
            argumentKinds: [.string],
            siteCount: 5,
            observedLiterals: Array(repeating: ["Date()"], count: 5)
        )
        let record = ConstructionRecord(entries: [entry])
        #expect(MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record) == nil)
    }

    @Test("UUID() in observedLiterals suppresses synthesis")
    func uuidLiteralSuppresses() {
        let entry = makeEntry(
            typeName: "Doc",
            argumentKinds: [.string],
            siteCount: 5,
            observedLiterals: Array(repeating: ["UUID()"], count: 5)
        )
        let record = ConstructionRecord(entries: [entry])
        #expect(MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record) == nil)
    }

    @Test("Date.now in observedLiterals suppresses synthesis")
    func dateNowSuppresses() {
        let entry = makeEntry(
            typeName: "Doc",
            argumentKinds: [.string],
            siteCount: 5,
            observedLiterals: Array(repeating: ["Date.now"], count: 5)
        )
        let record = ConstructionRecord(entries: [entry])
        #expect(MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record) == nil)
    }

    @Test("Mixed: any non-det literal in any position suppresses synthesis")
    func mixedNonDetSuppresses() {
        // First arg literal `"fixed"`, second arg `Date()`.
        // Even though one is a real string literal, Date() in the
        // second position vetoes the entire site's mock inference.
        let entry = makeEntry(
            typeName: "Doc",
            argumentKinds: [.string, .string],
            siteCount: 5,
            observedLiterals: Array(repeating: ["\"fixed\"", "Date()"], count: 5)
        )
        let record = ConstructionRecord(entries: [entry])
        #expect(MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record) == nil)
    }

    @Test("Int.random(in:) suffix match suppresses synthesis")
    func randomSuffixSuppresses() {
        let entry = makeEntry(
            typeName: "Doc",
            argumentKinds: [.integer],
            siteCount: 5,
            observedLiterals: Array(repeating: ["Int.random(in: 0...100)"], count: 5)
        )
        let record = ConstructionRecord(entries: [entry])
        #expect(MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record) == nil)
    }

    @Test("Pure-literal entry still synthesizes a generator (M4.3 baseline preserved)")
    func pureLiteralEntryStillSynthesizes() throws {
        let entry = makeEntry(
            typeName: "Money",
            argumentKinds: [.integer, .string],
            siteCount: 5,
            observedLiterals: Array(repeating: ["100", "\"USD\""], count: 5)
        )
        let record = ConstructionRecord(entries: [entry])
        let result = try #require(
            MockGeneratorSynthesizer.synthesize(typeName: "Money", record: record)
        )
        #expect(result.typeName == "Money")
        #expect(result.argumentSpec.count == 2)
    }

    @Test("Below-threshold record returns nil regardless of literals (M4.3 invariant)")
    func belowThresholdReturnsNil() {
        let entry = makeEntry(
            typeName: "Doc",
            argumentKinds: [.string],
            siteCount: 2,  // < 3 threshold
            observedLiterals: Array(repeating: ["\"fixed\""], count: 2)
        )
        let record = ConstructionRecord(entries: [entry])
        #expect(MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record) == nil)
    }

    @Test("Multi-shape record returns nil regardless of literals (M4.3 invariant)")
    func multiShapeReturnsNil() {
        let entry1 = makeEntry(
            typeName: "Doc",
            argumentKinds: [.string],
            siteCount: 5,
            observedLiterals: Array(repeating: ["\"a\""], count: 5)
        )
        let entry2 = makeEntry(
            typeName: "Doc",
            argumentKinds: [.integer],
            siteCount: 5,
            observedLiterals: Array(repeating: ["1"], count: 5)
        )
        let record = ConstructionRecord(entries: [entry1, entry2])
        #expect(MockGeneratorSynthesizer.synthesize(typeName: "Doc", record: record) == nil)
    }

    @Test("containsNonDeterministicLiteral helper detects each curated pattern")
    func helperDetectsCuratedPatterns() {
        let patterns = [
            "Date()",
            "Date.now",
            "UUID()",
            "URLSession.shared",
            "arc4random()",
            "rand()",
            "Int.random()",
            "Bool.random(in: 0...1)"
        ]
        for pattern in patterns {
            let entry = makeEntry(
                typeName: "T",
                argumentKinds: [.string],
                siteCount: 1,
                observedLiterals: [[pattern]]
            )
            #expect(
                MockGeneratorSynthesizer.containsNonDeterministicLiteral(in: entry),
                "Pattern '\(pattern)' should match the curated non-deterministic list"
            )
        }
    }

    @Test("containsNonDeterministicLiteral helper does NOT match plain literals")
    func helperDoesNotMatchPlainLiterals() {
        let plainLiterals = [
            "42",
            "\"hello\"",
            "true",
            "3.14",
            "\"Date is a noun\""
        ]
        for literal in plainLiterals {
            let entry = makeEntry(
                typeName: "T",
                argumentKinds: [.string],
                siteCount: 1,
                observedLiterals: [[literal]]
            )
            #expect(
                !MockGeneratorSynthesizer.containsNonDeterministicLiteral(in: entry),
                "Plain literal '\(literal)' should not match"
            )
        }
    }

    // MARK: - Fixture helpers

    private func makeEntry(
        typeName: String,
        argumentKinds: [ParameterizedValue.Kind],
        siteCount: Int,
        observedLiterals: [[String]]
    ) -> ConstructionRecordEntry {
        let arguments = argumentKinds.enumerated().map { offset, kind in
            ConstructionShape.Argument(label: "arg\(offset)", kind: kind)
        }
        return ConstructionRecordEntry(
            typeName: typeName,
            shape: ConstructionShape(arguments: arguments),
            siteCount: siteCount,
            observedLiterals: observedLiterals
        )
    }
}
