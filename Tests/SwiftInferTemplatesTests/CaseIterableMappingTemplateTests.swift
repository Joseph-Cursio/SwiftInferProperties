import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The `CaseIterable`-mapping family — the two laws that quantify over
/// `allCases` rather than over a function's inputs.
///
/// Both are name-conjectured, and the test that matters most is the **negative**
/// one: a classifier mapping many cases onto few is correct code, and proposing
/// injectivity for it would be a false positive on every enum in existence. The
/// two laws must split cleanly on the same shape.
@Suite("CaseIterable mapping — key injectivity and case coverage")
struct CaseIterableMappingTemplateTests {

    private static let loc = SourceLocation(file: "RuleIdentifier.swift", line: 241, column: 5)

    private func mapping(
        _ name: String,
        returns: String?,
        on type: String? = "RuleIdentifier",
        params: [Parameter] = [],
        isStatic: Bool = false,
        throws throwing: Bool = false,
        computed: Bool = true
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params,
            returnTypeText: returns,
            isThrows: throwing,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: Self.loc,
            containingTypeName: type,
            bodySignals: .empty,
            isComputedProperty: computed
        )
    }

    private func enumShape(
        _ name: String,
        cases: [String],
        inherits: [String] = ["String", "CaseIterable"]
    ) -> TypeShape {
        TypeShape(
            name: name,
            kind: .enum,
            inheritedTypes: inherits,
            hasUserGen: false,
            enumCases: cases.map { EnumCase(name: $0) }
        )
    }

    /// The road-test carriers: a 3-case `CaseIterable` domain, a category
    /// codomain carrying `.other`, and a codomain with no sink.
    private var shapes: [String: TypeShape] {
        [
            "RuleIdentifier": enumShape("RuleIdentifier", cases: ["forceTry", "magicNumber", "fatView"]),
            "PatternCategory": enumShape(
                "PatternCategory", cases: ["codeQuality", "performance", "other"], inherits: ["CaseIterable"]
            ),
            "Severity": enumShape("Severity", cases: ["error", "warning", "info"], inherits: ["CaseIterable"]),
            "Config": TypeShape(name: "Config", kind: .struct, inheritedTypes: [], hasUserGen: false)
        ]
    }

    // MARK: - Key injectivity fires

    @Test("a key-named mapping into String owes distinctness across allCases")
    func keyMappingFires() throws {
        let suggestion = try #require(
            CaseIterableMappingTemplate.suggest(
                for: mapping("suppressionKey", returns: "String"), shapesByName: shapes
            )
        )
        #expect(suggestion.templateName == "caseiterable-key-injectivity")
        #expect(suggestion.carrier == "RuleIdentifier")
        // The law names the member and the case count, so the reader can act on it.
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: " ")
        #expect(caveats.contains("Set(allCases.map(\\.suppressionKey)).count == allCases.count"))
        #expect(caveats.contains("EXHAUSTIVELY"))
        #expect(caveats.contains("3 cases"))
    }

    @Test(
        "every curated key noun is recognised as a suffix",
        arguments: ["suppressionKey", "ruleIdentifier", "wireId", "urlSlug", "errorCode", "glyphSymbol"]
    )
    func curatedKeyNounsFire(name: String) {
        let suggestion = CaseIterableMappingTemplate.suggest(
            for: mapping(name, returns: "String"), shapesByName: shapes
        )
        #expect(suggestion?.templateName == "caseiterable-key-injectivity")
    }

    /// `name`-shaped members are excluded on purpose. Two cases sharing a
    /// human-readable label is ordinary code, and this template is admitted to
    /// `roleEntailedTemplates` — where a law that can cry wolf does not belong.
    @Test(
        "label-shaped nouns are NOT treated as identifiers",
        arguments: ["displayName", "shortName", "categoryTag", "abbreviation"]
    )
    func labelNounsDecline(name: String) {
        let suggestion = CaseIterableMappingTemplate.suggest(
            for: mapping(name, returns: "String"), shapesByName: shapes
        )
        #expect(suggestion == nil)
    }

    // MARK: - Key injectivity declines

    /// The load-bearing negative. `category` is a many-to-one classifier and
    /// proposing distinctness for it would fail on correct code.
    @Test("a classifier into another enum is NOT proposed as injective")
    func classifierIsNotProposedInjective() {
        let suggestion = CaseIterableMappingTemplate.suggest(
            for: mapping("category", returns: "PatternCategory"), shapesByName: shapes
        )
        #expect(suggestion == nil)
    }

    @Test("a non-key name on the same shape earns nothing")
    func nonKeyNameDeclines() {
        let suggestion = CaseIterableMappingTemplate.suggest(
            for: mapping("descriptionText", returns: "String"), shapesByName: shapes
        )
        #expect(suggestion == nil)
    }

    @Test("a non-CaseIterable enum is out of scope")
    func nonCaseIterableDeclines() {
        let plain = ["RuleIdentifier": enumShape("RuleIdentifier", cases: ["a", "b"], inherits: ["String"])]
        let suggestion = CaseIterableMappingTemplate.suggest(
            for: mapping("suppressionKey", returns: "String"), shapesByName: plain
        )
        #expect(suggestion == nil)
    }

    @Test("a struct carrier is out of scope — allCases is what the law quantifies over")
    func structCarrierDeclines() {
        let suggestion = CaseIterableMappingTemplate.suggest(
            for: mapping("suppressionKey", returns: "String", on: "Config"), shapesByName: shapes
        )
        #expect(suggestion == nil)
    }

    /// A single-case enum satisfies both laws vacuously, so proposing either is noise.
    @Test("a single-case enum earns nothing")
    func singleCaseEnumDeclines() {
        let tiny = ["Solo": enumShape("Solo", cases: ["only"])]
        let suggestion = CaseIterableMappingTemplate.suggest(
            for: mapping("identifier", returns: "String", on: "Solo"), shapesByName: tiny
        )
        #expect(suggestion == nil)
    }

    @Test("a member taking arguments is not a mapping out of the case list")
    func parameterisedMemberDeclines() {
        let summary = mapping(
            "keyed", returns: "String",
            params: [Parameter(label: "for", internalName: "style", typeText: "Int", isInout: false)]
        )
        #expect(CaseIterableMappingTemplate.suggest(for: summary, shapesByName: shapes) == nil)
    }

    @Test("a static member has no case to map from")
    func staticMemberDeclines() {
        let suggestion = CaseIterableMappingTemplate.suggest(
            for: mapping("identifier", returns: "String", isStatic: true), shapesByName: shapes
        )
        #expect(suggestion == nil)
    }

    @Test("a throwing member is out of scope")
    func throwingMemberDeclines() {
        let suggestion = CaseIterableMappingTemplate.suggest(
            for: mapping("identifier", returns: "String", throws: true), shapesByName: shapes
        )
        #expect(suggestion == nil)
    }

    // MARK: - Case coverage fires

    @Test("a classifier into an enum carrying a sink case owes coverage")
    func coverageFires() throws {
        let suggestion = try #require(
            CaseIterableMappingTemplate.coverageSuggestion(
                for: mapping("category", returns: "PatternCategory"), shapesByName: shapes
            )
        )
        #expect(suggestion.templateName == "caseiterable-case-coverage")
        #expect(suggestion.carrier == "RuleIdentifier")
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: " ")
        // The sink is named from the codomain's own case list, not guessed.
        #expect(caveats.contains(".other"))
        // And the law is the written-down-exceptions form, not "nothing maps to it".
        #expect(caveats.contains("written-down"))
        #expect(caveats.contains("EXHAUSTIVE `switch` IS NOT THIS LAW"))
    }

    // MARK: - Case coverage declines

    /// The sink has to be *found*, not assumed: a codomain with no such case
    /// gives the law nothing to be false against.
    @Test("a codomain with no sink case earns nothing")
    func codomainWithoutSinkDeclines() {
        let suggestion = CaseIterableMappingTemplate.coverageSuggestion(
            for: mapping("severity", returns: "Severity"), shapesByName: shapes
        )
        #expect(suggestion == nil)
    }

    @Test("a scalar codomain is a key, not a classification")
    func scalarCodomainDeclinesCoverage() {
        let suggestion = CaseIterableMappingTemplate.coverageSuggestion(
            for: mapping("suppressionKey", returns: "String"), shapesByName: shapes
        )
        #expect(suggestion == nil)
    }

    /// `Foo -> Foo` is an endomorphism; idempotence and involution already speak
    /// for that shape, and coverage would be a duplicate proposal.
    @Test("a self-mapping is left to the endomorphism templates")
    func selfMappingDeclines() {
        let shapesWithSink = [
            "PatternCategory": enumShape(
                "PatternCategory", cases: ["codeQuality", "other"], inherits: ["CaseIterable"]
            )
        ]
        let suggestion = CaseIterableMappingTemplate.coverageSuggestion(
            for: mapping("normalized", returns: "PatternCategory", on: "PatternCategory"),
            shapesByName: shapesWithSink
        )
        #expect(suggestion == nil)
    }

    // MARK: - Role entailment

    /// The deliberate asymmetry between the two laws, pinned because nothing
    /// else guards it and getting it wrong is the failure `Refutability` is
    /// written against.
    ///
    /// **Injectivity is role-entailed**: a member claiming to *identify* a case
    /// cannot correctly return the same value for two of them, so the law
    /// surfaces on a default run even at `Possible` tier.
    ///
    /// **Coverage is not**: routing some cases to a sink can be entirely correct
    /// — this project's own `.unknown` and `.fileParsingError` sentinels do — so
    /// a correct implementation can fail it. It stays below the cut. Admitting
    /// it would hand readers a test that goes red for no reason, which
    /// `Refutability` argues is worse than proposing nothing at all.
    @Test("only the injectivity half is role-entailed")
    func roleEntailmentSplitIsDeliberate() throws {
        let key = try #require(
            CaseIterableMappingTemplate.suggest(
                for: mapping("suppressionKey", returns: "String"), shapesByName: shapes
            )
        )
        let coverage = try #require(
            CaseIterableMappingTemplate.coverageSuggestion(
                for: mapping("category", returns: "PatternCategory"), shapesByName: shapes
            )
        )

        // Both can catch a bug…
        #expect(Refutability.isRefutable(key))
        #expect(Refutability.isRefutable(coverage))

        // …but only one cannot cry wolf on correct code.
        #expect(Refutability.isRoleEntailed(key))
        #expect(Refutability.isRoleEntailed(coverage) == false)

        #expect(Refutability.isWorthSurfacingBelowCut(key))
        #expect(Refutability.isWorthSurfacingBelowCut(coverage) == false)
    }

    // MARK: - Mutual exclusion

    /// The two laws must never both fire: a key returns a scalar, a classifier
    /// returns an enum, and no member is both.
    @Test(
        "at most one of the two laws fires for any member",
        arguments: [
            ("suppressionKey", "String"), ("category", "PatternCategory"),
            ("severity", "Severity"), ("descriptionText", "String")
        ]
    )
    func lawsAreMutuallyExclusive(name: String, returns: String) {
        let summary = mapping(name, returns: returns)
        var fired: [Suggestion] = []
        if let key = CaseIterableMappingTemplate.suggest(for: summary, shapesByName: shapes) {
            fired.append(key)
        }
        if let coverage = CaseIterableMappingTemplate.coverageSuggestion(
            for: summary, shapesByName: shapes
        ) {
            fired.append(coverage)
        }
        #expect(fired.count <= 1, "\(name) fired \(fired.count) laws: \(fired.map(\.templateName))")
    }
}
