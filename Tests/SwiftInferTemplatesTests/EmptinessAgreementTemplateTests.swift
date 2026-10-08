import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// A predicate and a count on one type, named for the same thing, owe each other agreement:
/// `hasIssues == (totalIssueCount > 0)`. Measured on SwiftLintRuleStudioCore's
/// `CompatibilityReport`, where both members were seeded, `discover` proposed only
/// `measure-non-negativity`, and both `||` → `&&` mutants in `hasIssues` went unreached.
@Suite("emptiness-agreement — a predicate and a count named for one thing agree")
struct EmptinessAgreementTemplateTests {

    private static let source = """
        public struct Report {
            public var deprecated: [String]
            public var removed: [String]
            public var hasIssues: Bool { !deprecated.isEmpty || !removed.isEmpty }
            public var totalIssueCount: Int { deprecated.count + removed.count }
            public var retryCount: Int { 0 }
            public var hasRetries: Bool { false }
            public var hasPendingWork: Bool { false }
        }
        public struct Bag {
            public var items: [Int]
            public var isEmpty: Bool { items.isEmpty }
            public var count: Int { items.count }
            public static var hasDefaults: Bool { true }
        }
        """

    private static func pairs() -> [EmptinessAgreementPair] {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Report.swift")
        return EmptinessAgreementPairing.candidates(in: corpus.summaries)
    }

    @Test("has<Thing> pairs with the count that names the thing; isEmpty pairs with count, inverted")
    func pairsByName() {
        let found = Self.pairs().map { "\($0.predicate.name)|\($0.measure.name)|\($0.holdsWhenPositive)" }
        #expect(Set(found) == Set([
            "hasIssues|totalIssueCount|true",
            "hasRetries|retryCount|true",
            "isEmpty|count|false"
        ]), "found \(found.sorted())")
    }

    @Test("names that do not pair", arguments: [
        ("hasPendingWork", "totalIssueCount"), ("hasIssues", "retryCount"), ("has", "count"),
        ("hashValue", "count"), ("isEmpty", "totalIssueCount"), ("isValid", "count")
    ])
    func unpaired(predicate: String, measure: String) {
        #expect(EmptinessAgreementPairing.polarity(predicate: predicate, measure: measure) == nil)
    }

    @Test("the suggestion is a Likely-tier conjecture over both members, stating the law")
    func suggestion() throws {
        let pair = try #require(Self.pairs().first { $0.predicate.name == "hasIssues" })
        let suggestion = try #require(EmptinessAgreementTemplate.suggest(for: pair))
        #expect(suggestion.templateName == "emptiness-agreement")
        #expect(suggestion.score.tier == .likely)
        #expect(suggestion.evidence.map(\.displayName) == ["hasIssues()", "totalIssueCount()"])
        #expect(suggestion.explainability.whyMightBeWrong.first?.contains("hasIssues == (totalIssueCount > 0)") == true)
        #expect(Refutability.isRefutable(suggestion))
    }

    @Test("the stub reads both members off one drawn value")
    func stub() throws {
        let pair = try #require(Self.pairs().first { $0.predicate.name == "isEmpty" })
        let suggestion = try #require(EmptinessAgreementTemplate.suggest(for: pair))
        let predicate = try #require(CalleeReference(evidence: suggestion.evidence[0]))
        let measure = try #require(CalleeReference(evidence: suggestion.evidence[1]))
        let stub = LiftedTestEmitter.emptinessAgreement(
            predicate: predicate, measure: measure, holdsWhenPositive: false,
            carrier: ("Bag", "Bag.gen()"), seed: SamplingSeed.derive(from: suggestion.identity)
        )
        #expect(stub.contains("{ (value: Bag) in value.isEmpty == (value.count == 0) }"), "got:\n\(stub)")
        #expect(stub.contains("func isEmpty_agreesWith_count()"))
    }
}
