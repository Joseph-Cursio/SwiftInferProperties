import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("MonotonicityTemplate — type pattern (ordered codomain)")
struct MonotonicityTemplateTypePatternTests {

    @Test("Single param T -> Int with no naming signal scores 25 (Possible)")
    func orderedCodomainAlone() {
        let summary = makeMonotonicitySummary(
            name: "calculate",
            returnType: "Int",
            paramType: "Widget"
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
                returnType: codomain,
                paramType: "Widget"
            )
            #expect(
                MonotonicityTemplate.suggest(for: summary) != nil,
                "Expected \(codomain) to match the curated codomain set"
            )
        }
    }

    @Test("String codomain is excluded (dogfood: lexicographic order rarely tracks input)")
    func stringCodomainExcluded() {
        // `String` was removed from comparableCodomains — transform/IO verbs
        // returning String (serialize/generateMarkdown/fetchConfig) are not
        // monotone, and dogfooding showed bare `X -> String` producing only
        // Possible-tier false positives. Even a curated-verb name must not
        // resurrect a String-codomain pick.
        #expect(!MonotonicityTemplate.comparableCodomains.contains("String"))
        let summary = makeMonotonicitySummary(
            name: "score",
            returnType: "String",
            // curated verb — still must not fire on String
            paramType: "Widget"
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    @Test("Non-Comparable codomain does not match")
    func nonComparableCodomainRejected() {
        let summary = makeMonotonicitySummary(
            name: "calculate",
            returnType: "[String]",
            paramType: "Widget"
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    @Test("User-declared Comparable type is not recognised (textual cap per §5.2)")
    func userDeclaredComparableNotRecognised() {
        let summary = makeMonotonicitySummary(
            name: "score",
            returnType: "MyScore",
            paramType: "Widget"
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    @Test("Multi-parameter function does not match the type pattern")
    func multiParameterRejected() {
        let summary = makeMonotonicitySummary(
            name: "score",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Widget", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "Widget", isInout: false),
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
            returnType: "Int",
            paramType: "Widget",
            isMutating: true
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    @Test("Implicit Void return is rejected")
    func implicitVoidRejected() {
        let summary = makeMonotonicitySummary(
            name: "score",
            returnType: nil,
            paramType: "Widget"
        )
        #expect(MonotonicityTemplate.suggest(for: summary) == nil)
    }

    @Test("T -> T over a Comparable codomain still matches (overlap with idempotence is fine)")
    func sameTypeComparableMatches() {
        let summary = makeMonotonicitySummary(
            name: "calculate",
            returnType: "Int",
            paramType: "Int"
        )
        let suggestion = MonotonicityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 25)
        #expect(suggestion?.score.tier == .possible)
    }
}
