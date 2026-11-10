import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// MARK: - Shared helpers

func makeMonotonicitySummary(
    name: String,
    returnType: String?,
    paramType: String? = nil,
    parameters explicitParameters: [Parameter]? = nil,
    isMutating: Bool = false,
    bodySignals: BodySignals = .empty
) -> FunctionSummary {
    let parameters: [Parameter]
    if let explicitParameters {
        parameters = explicitParameters
    } else if let paramType {
        parameters = [Parameter(label: nil, internalName: "value", typeText: paramType, isInout: false)]
    } else {
        parameters = []
    }
    return FunctionSummary(
        name: name,
        parameters: parameters,
        returnTypeText: returnType,
        isThrows: false,
        isAsync: false,
        isMutating: isMutating,
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 1, column: 1),
        containingTypeName: nil,
        bodySignals: bodySignals
    )
}

func makeMonotonicitySummary(
    name: String,
    parameters: [Parameter],
    returnType: String?
) -> FunctionSummary {
    makeMonotonicitySummary(
        name: name,
        returnType: returnType,
        paramType: nil,
        parameters: parameters,
        isMutating: false,
        bodySignals: .empty
    )
}

@Suite("MonotonicityTemplate — naming, vocabulary, tier policy")
struct MonotonicityTemplateNamingTests {

    // MARK: - Curated naming verbs

    @Test("Curated verb on T -> Int scores 35 (Possible — still under 40 per §5.2)")
    func curatedVerbStaysPossible() {
        let summary = makeMonotonicitySummary(
            name: "length",
            returnType: "Int",
            paramType: "String"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 35)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("Every curated verb on a curated codomain produces a Possible-tier suggestion")
    func everyCuratedVerbProducesSuggestion() {
        for verb in MonotonicityTemplate.curatedVerbs {
            let summary = makeMonotonicitySummary(
                name: verb,
                returnType: "Int",
                paramType: "Widget"
            )
            let suggestion = MonotonicityTemplate.suggest(for: summary)
            #expect(suggestion?.score.total == 35, "verb '\(verb)' did not produce 35")
            #expect(suggestion?.score.tier == .possible, "verb '\(verb)' did not stay in Possible")
        }
    }

    @Test("Curated verb does not match when codomain is unrecognised")
    func curatedVerbNeedsCuratedCodomain() {
        let summary = makeMonotonicitySummary(
            name: "length",
            returnType: "[Character]",
            paramType: "String"
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Curated suffix patterns

    @Test("`userCount` matches the curated `Count` suffix")
    func curatedSuffixCountMatches() {
        let summary = makeMonotonicitySummary(
            name: "userCount",
            returnType: "Int",
            paramType: "Org"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 35)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("`pageSize` matches the curated `Size` suffix")
    func curatedSuffixSizeMatches() {
        let summary = makeMonotonicitySummary(
            name: "pageSize",
            returnType: "Int",
            paramType: "Document"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 35)
    }

    @Test("Bare suffix string (`Count`) does not match — curated exact-match handles `count`")
    func bareSuffixDoesNotDoubleMatch() {
        let summary = makeMonotonicitySummary(
            name: "Count",
            returnType: "Int",
            paramType: "Org"
        )
        // `Count` ≠ curated verb `count` (case-sensitive); has no prefix
        // before the suffix. Falls through to the type-pattern signal alone.
        let suggestion = MonotonicityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 25)
    }

    // MARK: - Project vocabulary fallback (PRD §4.5)

    @Test("Project-vocabulary verb match scores 35 when curated list misses")
    func projectVocabularyMatch() {
        let summary = makeMonotonicitySummary(
            name: "rank",
            returnType: "Int",
            paramType: "User"
        )
        let vocab = Vocabulary(monotonicityVerbs: ["rank"])
        let suggestion = MonotonicityTemplate.suggest(for: summary, vocabulary: vocab)
        #expect(suggestion?.score.total == 35)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("Curated verb takes precedence — project vocab does not double-fire")
    func curatedVerbOverridesProjectVocab() {
        let summary = makeMonotonicitySummary(
            name: "length",
            returnType: "Int",
            paramType: "String"
        )
        let vocab = Vocabulary(monotonicityVerbs: ["length"])
        let suggestion = MonotonicityTemplate.suggest(for: summary, vocabulary: vocab)
        // Curated wins — total stays 35, not 45.
        #expect(suggestion?.score.total == 35)
    }

    @Test("Empty vocabulary falls back to curated set alone")
    func emptyVocabularyMatchesCuratedOnly() {
        let summary = makeMonotonicitySummary(
            name: "irrelevantName",
            returnType: "Int",
            paramType: "Widget"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary, vocabulary: .empty)
        #expect(suggestion?.score.total == 25)
    }

    // MARK: - Tier policy (§5.2 Possible-by-default)

    @Test("Maximum signal combination without escalation stays in Possible (under 40)")
    func maxScoreStaysPossibleWithoutEscalation() {
        let summary = makeMonotonicitySummary(
            name: "length",
            returnType: "Int",
            paramType: "String"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary)
        let total = try? #require(suggestion?.score.total)
        #expect((total ?? 0) < 40, "Without annotation/TestLifter, score must stay below the Likely threshold")
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("Suggestion identity reuses idempotence's canonical-signature shape under a monotonicity prefix")
    func identityReusesCanonicalSignature() {
        let summary = makeMonotonicitySummary(
            name: "length",
            returnType: "Int",
            paramType: "String"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary)
        let identity = try? #require(suggestion?.identity)
        // Canonical input prefixes with the template ID per PRD §7.5;
        // display form is `0x` + 16 uppercase hex chars.
        #expect(identity?.canonicalInput.hasPrefix("monotonicity|") == true)
        #expect(identity?.display.hasPrefix("0x") == true)
    }
}
