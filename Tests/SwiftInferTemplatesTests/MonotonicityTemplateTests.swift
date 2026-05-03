import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("MonotonicityTemplate — type pattern (ordered codomain)")
struct MonotonicityTemplateTypePatternTests {

    @Test("Single param T -> Int with no naming signal scores 25 (Possible)")
    func orderedCodomainAlone() {
        let summary = makeMonotonicitySummary(
            name: "calculate",
            paramType: "Widget",
            returnType: "Int"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 25)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("Each curated Comparable codomain matches the type pattern")
    func everyCuratedCodomainMatches() {
        for codomain in MonotonicityTemplate.comparableCodomains {
            let summary = makeMonotonicitySummary(
                name: "calculate",
                paramType: "Widget",
                returnType: codomain
            )
            #expect(
                MonotonicityTemplate.suggest(for: summary) != nil,
                "Expected \(codomain) to match the curated codomain set"
            )
        }
    }

    @Test("Non-Comparable codomain does not match")
    func nonComparableCodomainRejected() {
        let summary = makeMonotonicitySummary(
            name: "calculate",
            paramType: "Widget",
            returnType: "[String]"
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    @Test("User-declared Comparable type is not recognised (textual cap per §5.2)")
    func userDeclaredComparableNotRecognised() {
        let summary = makeMonotonicitySummary(
            name: "score",
            paramType: "Widget",
            returnType: "MyScore"
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    @Test("Multi-parameter function does not match the type pattern")
    func multiParameterRejected() {
        let summary = makeMonotonicitySummary(
            name: "score",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Widget", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "Widget", isInout: false)
            ],
            returnType: "Int"
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    @Test("Zero-parameter function does not match the type pattern")
    func zeroParameterRejected() {
        let summary = makeMonotonicitySummary(
            name: "score",
            parameters: [],
            returnType: "Int"
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    @Test("inout parameter disqualifies the type pattern")
    func inoutDisqualifies() {
        let summary = makeMonotonicitySummary(
            name: "score",
            parameters: [Parameter(label: nil, internalName: "v", typeText: "Widget", isInout: true)],
            returnType: "Int"
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    @Test("mutating disqualifies the type pattern")
    func mutatingDisqualifies() {
        let summary = makeMonotonicitySummary(
            name: "score",
            paramType: "Widget",
            returnType: "Int",
            isMutating: true
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    @Test("Implicit Void return is rejected")
    func implicitVoidRejected() {
        let summary = makeMonotonicitySummary(
            name: "score",
            paramType: "Widget",
            returnType: nil
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    @Test("T -> T over a Comparable codomain still matches (overlap with idempotence is fine)")
    func sameTypeComparableMatches() {
        let summary = makeMonotonicitySummary(
            name: "calculate",
            paramType: "Int",
            returnType: "Int"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 25)
        #expect(suggestion?.score.tier == .possible)
    }
}

@Suite("MonotonicityTemplate — naming, vocabulary, tier policy")
struct MonotonicityTemplateNamingTests {

    // MARK: - Curated naming verbs

    @Test("Curated verb on T -> Int scores 35 (Possible — still under 40 per §5.2)")
    func curatedVerbStaysPossible() {
        let summary = makeMonotonicitySummary(
            name: "length",
            paramType: "String",
            returnType: "Int"
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
                paramType: "Widget",
                returnType: "Int"
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
            paramType: "String",
            returnType: "[Character]"
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Curated suffix patterns

    @Test("`userCount` matches the curated `Count` suffix")
    func curatedSuffixCountMatches() {
        let summary = makeMonotonicitySummary(
            name: "userCount",
            paramType: "Org",
            returnType: "Int"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 35)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("`pageSize` matches the curated `Size` suffix")
    func curatedSuffixSizeMatches() {
        let summary = makeMonotonicitySummary(
            name: "pageSize",
            paramType: "Document",
            returnType: "Int"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 35)
    }

    @Test("Bare suffix string (`Count`) does not match — curated exact-match handles `count`")
    func bareSuffixDoesNotDoubleMatch() {
        let summary = makeMonotonicitySummary(
            name: "Count",
            paramType: "Org",
            returnType: "Int"
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
            paramType: "User",
            returnType: "Int"
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
            paramType: "String",
            returnType: "Int"
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
            paramType: "Widget",
            returnType: "Int"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary, vocabulary: .empty)
        #expect(suggestion?.score.total == 25)
    }

    // MARK: - Tier policy (§5.2 Possible-by-default)

    @Test("Maximum signal combination without escalation stays in Possible (under 40)")
    func maxScoreStaysPossibleWithoutEscalation() {
        let summary = makeMonotonicitySummary(
            name: "length",
            paramType: "String",
            returnType: "Int"
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
            paramType: "String",
            returnType: "Int"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary)
        let identity = try? #require(suggestion?.identity)
        // Canonical input prefixes with the template ID per PRD §7.5;
        // display form is `0x` + 16 uppercase hex chars.
        #expect(identity?.canonicalInput.hasPrefix("monotonicity|") == true)
        #expect(identity?.display.hasPrefix("0x") == true)
    }
}

// MARK: - Shared helpers

private func makeMonotonicitySummary(
    name: String,
    paramType: String? = nil,
    parameters explicitParameters: [Parameter]? = nil,
    returnType: String?,
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

private func makeMonotonicitySummary(
    name: String,
    parameters: [Parameter],
    returnType: String?
) -> FunctionSummary {
    makeMonotonicitySummary(
        name: name,
        paramType: nil,
        parameters: parameters,
        returnType: returnType,
        isMutating: false,
        bodySignals: .empty
    )
}
