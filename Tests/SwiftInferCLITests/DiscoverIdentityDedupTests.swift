import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **Two rows with one identity are one law.**
///
/// `SuggestionIdentity` is `SHA256(template ID + canonical signature)`. Every consumer but
/// the renderer already treated equal identities as one claim — one skip marker suppresses
/// them all, one verify record answers for them all, one index entry stores them — so the
/// rendered count was the outlier, not the truth.
///
/// Measured on this repo (findings §10.4): **174 rendered rows against 170 distinct
/// identities**, with all four extras landing in `Strong` and taking it from 3 to 7.
/// The cause was five golden tests in `GeneratorSelectionIntegrationTests`, each asserting
/// `render(x) == expectedRender(...)`, lifting correctly to one law.
@Suite("Discover — identity dedup")
struct DiscoverIdentityDedupTests {

    private func suggestion(
        template: String,
        score: Int,
        identity: String,
        why: [String] = []
    ) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [],
            score: Score(signals: [
                Signal(kind: .exactNameMatch, weight: score, detail: "w")
            ]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: why, whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: identity)
        )
    }

    @Test("distinct identities are left alone, in order")
    func distinctIdentitiesUntouched() {
        let input = [
            suggestion(template: "idempotence", score: 80, identity: "a"),
            suggestion(template: "round-trip", score: 60, identity: "bee"),
            suggestion(template: "predicate", score: 20, identity: "cee")
        ]
        let output = SwiftInferCommand.Discover.dedupedByIdentity(input)
        #expect(output.count == 3)
        #expect(output.map(\.identity.normalized) == input.map(\.identity.normalized))
        // Pass-through must be exact — no explainability line on a row that collapsed nothing.
        // Hoisted out of `#expect`: `allSatisfy` is `rethrows`, and inside the macro
        // expansion that reads as a throwing call the macro will not mark with `try`.
        let noneAnnotated = output.allSatisfy(\.explainability.whySuggested.isEmpty)
        #expect(noneAnnotated)
    }

    /// **The measured case.** Five copies of one law collapse to one row.
    @Test("five copies of one law collapse to one")
    func fiveCopiesCollapse() {
        let copies = (0..<5).map { _ in
            suggestion(template: "differential-equivalence", score: 80, identity: "same")
        }
        let output = SwiftInferCommand.Discover.dedupedByIdentity(copies)
        #expect(output.count == 1)
        #expect(output[0].templateName == "differential-equivalence")
    }

    /// The collapse is reported. A dedup that silently drops rows produces output that looks
    /// like it covered everything — the "no silent caps" failure.
    @Test("the survivor says how many collapsed into it")
    func collapseIsReported() {
        let copies = (0..<5).map { _ in
            suggestion(template: "differential-equivalence", score: 80, identity: "same")
        }
        let output = SwiftInferCommand.Discover.dedupedByIdentity(copies)
        let why = output[0].explainability.whySuggested.joined(separator: " ")
        #expect(why.contains("Stated 5 times"))
        #expect(why.contains("corroboration"), "five tests asserting one law is corroboration")
        // It must not name test methods: LiftedOrigin renders `<test-body>:0` on this path,
        // so there is nothing truthful to name. If origins become real, this assertion is
        // the one to revisit.
        #expect(!why.contains("testMethod"))
    }

    /// **First wins, and the order is the point.** The pipeline concatenates
    /// `artifacts.suggestions` (TemplateEngine) ahead of promoted lifted rows, so a law
    /// derived structurally outranks the same law recovered from a test body — the same
    /// precedence `crossValidationKey` suppression applies one step earlier.
    @Test("the first occurrence survives, so TemplateEngine outranks lifted")
    func firstOccurrenceWins() {
        let fromEngine = suggestion(
            template: "idempotence", score: 80, identity: "same", why: ["from the engine"]
        )
        let fromTest = suggestion(
            template: "idempotence", score: 80, identity: "same", why: ["from a test body"]
        )
        let output = SwiftInferCommand.Discover.dedupedByIdentity([fromEngine, fromTest])
        #expect(output.count == 1)
        #expect(output[0].explainability.whySuggested.first == "from the engine")
    }

    /// Deduping must not disturb rows around the duplicates.
    @Test("surrounding rows keep their positions")
    func orderIsPreserved() {
        let input = [
            suggestion(template: "idempotence", score: 80, identity: "first"),
            suggestion(template: "differential-equivalence", score: 80, identity: "dup"),
            suggestion(template: "round-trip", score: 60, identity: "middle"),
            suggestion(template: "differential-equivalence", score: 80, identity: "dup"),
            suggestion(template: "predicate", score: 20, identity: "last")
        ]
        let output = SwiftInferCommand.Discover.dedupedByIdentity(input)
        #expect(output.count == 4)
        #expect(output.map(\.templateName) == [
            "idempotence", "differential-equivalence", "round-trip", "predicate"
        ])
    }

    @Test("an empty list is unchanged")
    func emptyIsUnchanged() {
        #expect(SwiftInferCommand.Discover.dedupedByIdentity([]).isEmpty)
    }
}
