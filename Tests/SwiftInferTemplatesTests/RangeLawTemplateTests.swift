import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The two range laws, from SwiftLintRuleStudioCore's survivors: `rulesAdded(from:to:)`, whose
/// `&&` → `||` mutant selects every version, and `AnalysisProgress.progress`, documented as
/// "(0.0 to 1.0)" and called by no test.
@Suite("range laws — an empty range selects nothing; a result stays in its documented range")
struct RangeLawTemplateTests {

    private static let source = """
        public enum Deprecations {
            public static func rulesAdded(from fromVersion: String, to toVersion: String) -> [String] { [] }
            public static func rulesBetween(from fromVersion: String, through toVersion: String) -> [String] { [] }
            public static func mixed(from start: Int, to end: String) -> [String] { [] }
            public static func count(from start: Int, to end: Int) -> Int { 0 }
        }
        public struct Progress {
            public let done: Int
            public let total: Int?
            /// Fraction of files processed (0.0 to 1.0)
            public var progress: Double { 0 }
            /// A percentage, between 0 and 100.
            public var percent: Int { 0 }
            /// Either 0...1 or 0...100, depending.
            public var ambiguous: Double { 0 }
            /// Index into the table.
            public var index: Int { 0 }
            /// Unit interval, half-open: 0..<1
            public var halfOpen: Double { 0 }
        }
        public struct Walker {
            public func steps(from start: Int, to end: Int) -> [Int] { [] }
        }
        """

    private static func summary(_ name: String) throws -> FunctionSummary {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Ranges.swift")
        return try #require(corpus.summaries.first { $0.name == name })
    }

    // MARK: - empty-range

    @Test("a static from:to: over one type returning a collection is a range selection")
    func emptyRangeApplies() throws {
        let suggestion = try #require(EmptyRangeTemplate.suggest(for: try Self.summary("rulesAdded")))
        #expect(suggestion.templateName == "empty-range")
        #expect(suggestion.score.tier == .likely)
        #expect(suggestion.explainability.whyMightBeWrong.first?.contains("f(from: v, to: v).isEmpty") == true)
    }

    @Test("not a range selection", arguments: ["rulesBetween", "mixed", "count", "steps"])
    func emptyRangeDeclines(name: String) throws {
        #expect(EmptyRangeTemplate.suggest(for: try Self.summary(name)) == nil)
    }

    @Test("the stub passes one drawn bound as both ends")
    func emptyRangeStub() throws {
        let suggestion = try #require(EmptyRangeTemplate.suggest(for: try Self.summary("rulesAdded")))
        let evidence = try #require(suggestion.evidence.first)
        let callee = try #require(CalleeReference(evidence: evidence))
        let stub = LiftedTestEmitter.emptyRange(
            callee: callee, bound: ("String", "Gen<String>.string()"),
            seed: SamplingSeed.derive(from: suggestion.identity)
        )
        #expect(stub.contains("Deprecations.rulesAdded(from: value, to: value).isEmpty"), "got:\n\(stub)")
    }

    // MARK: - documented-range

    @Test("the range shapes doc comments use", arguments: [
        ("Fraction of files processed (0.0 to 1.0)", "0.0", "1.0"),
        ("A ratio in 0...1.", "0", "1"),
        ("Clamped to [0, 255].", "0", "255"),
        ("A percentage, between 0 and 100.", "0", "100"),
        ("Ranges from -1 to 1.", "-1", "1"),
        ("Opacity, 0.0…1.0", "0.0", "1.0")
    ])
    func rangeShapes(doc: String, lower: String, upper: String) {
        #expect(DocumentedRangeTemplate.statedRange(in: doc) == DocumentedRange(lower: lower, upper: upper))
    }

    @Test("no range, several ranges, a reversed range, or a half-open one", arguments: [
        "Index into the table.", "Either 0...1 or 0...100, depending.", "From 10 to 1, counting down.",
        "Unit interval, half-open: 0..<1", "Version 1.2 to 1.3 of the format"
    ])
    func noRange(doc: String) {
        // The last is not one of the shapes: a bare `a to b` is read only inside parentheses or
        // after `from`, because prose names versions and spans that way.
        #expect(DocumentedRangeTemplate.statedRange(in: doc) == nil)
    }

    @Test("a numeric member documenting its range is proposed, carrying the bounds")
    func documentedRangeApplies() throws {
        let suggestion = try #require(DocumentedRangeTemplate.suggest(for: try Self.summary("progress")))
        #expect(suggestion.templateName == "documented-range")
        #expect(suggestion.score.tier == .likely)
        #expect(suggestion.match?.documentedRangeMatch == DocumentedRange(lower: "0.0", upper: "1.0"))
        let integer = try #require(DocumentedRangeTemplate.suggest(for: try Self.summary("percent")))
        #expect(integer.match?.documentedRangeMatch == DocumentedRange(lower: "0", upper: "100"))
    }

    @Test("not proposed without exactly one closed range", arguments: ["ambiguous", "index", "halfOpen"])
    func documentedRangeDeclines(name: String) throws {
        #expect(DocumentedRangeTemplate.suggest(for: try Self.summary(name)) == nil)
    }

    @Test("the stub checks the result as a Double against the stated bounds")
    func documentedRangeStub() throws {
        let suggestion = try #require(DocumentedRangeTemplate.suggest(for: try Self.summary("progress")))
        let evidence = try #require(suggestion.evidence.first)
        let callee = try #require(CalleeReference(evidence: evidence))
        let stub = LiftedTestEmitter.withinDocumentedRange(
            callee: callee, range: DocumentedRange(lower: "0.0", upper: "1.0"),
            seed: SamplingSeed.derive(from: suggestion.identity),
            generators: ["Progress.gen()"], argumentTypes: ["Progress"],
            failureLabel: "progress left its documented range"
        )
        #expect(stub.contains("(0.0...1.0 as ClosedRange<Double>).contains(Double(value.progress))"), "got:\n\(stub)")
    }
}
