import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Display order for `discover`'s default surface — strongest law first.
///
/// Two deliberate decisions had drifted into a contradiction. `PredicateTemplate`
/// scores totality at 20, arguing that surfacing it by default "would bury the
/// partition and comparator findings under a list of everything that returns a
/// `Bool`". Then `3e38e34` ruled that **a law the code OWES is never hidden**
/// and added `predicate` to `roleEntailedTemplates`, so the below-cut rescue
/// surfaces it.
///
/// Measured before the fix: `SwiftInferTemplates` rendered **56 score-20
/// predicates before the first score-80 finding**; `SwiftInferCore` 46 of 77.
/// Both decisions are right — the conflict was ordering, and sorting costs
/// neither of them anything.
@Suite("Discover — display order")
struct DiscoverDisplayOrderTests {

    private func suggestion(
        template: String,
        score: Int,
        identity: String
    ) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [],
            score: Score(signals: [
                Signal(kind: .exactNameMatch, weight: score, detail: "w")
            ]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: identity)
        )
    }

    @Test("a higher score sorts first")
    func higherScoreFirst() {
        let weak = suggestion(template: "predicate", score: 20, identity: "a")
        let strong = suggestion(template: "idempotence", score: 80, identity: "b")
        #expect(SwiftInferCommand.Discover.strongestFirst(strong, weak))
        #expect(!SwiftInferCommand.Discover.strongestFirst(weak, strong))
    }

    /// The measured case: score-20 predicates must not precede a score-80
    /// finding, whatever order the templates produced them in.
    @Test("predicates sort behind the findings the reader came for")
    func predicatesSortLast() {
        let produced = [
            suggestion(template: "predicate", score: 20, identity: "p1"),
            suggestion(template: "predicate", score: 20, identity: "p2"),
            suggestion(template: "idempotence", score: 80, identity: "i1"),
            suggestion(template: "predicate", score: 20, identity: "p3"),
            suggestion(template: "differential-equivalence", score: 80, identity: "d1")
        ]
        let ordered = produced.sorted(by: SwiftInferCommand.Discover.strongestFirst)
        #expect(ordered.prefix(2).allSatisfy { $0.score.total == 80 })
        #expect(ordered.suffix(3).allSatisfy { $0.templateName == "predicate" })
    }

    /// **PRD §16 #6 requires byte-identical output across runs**, and
    /// `sorted(by:)` is not a stable sort — equal scores would otherwise land
    /// in whatever order the templates happened to produce. The identity
    /// tiebreak makes the order total.
    @Test("equal scores break ties deterministically on identity")
    func equalScoresAreTotallyOrdered() {
        let alpha = suggestion(template: "predicate", score: 20, identity: "aaa")
        let beta = suggestion(template: "predicate", score: 20, identity: "bbb")
        #expect(
            SwiftInferCommand.Discover.strongestFirst(alpha, beta)
                != SwiftInferCommand.Discover.strongestFirst(beta, alpha),
            "the comparator must be asymmetric on equal scores, not return false both ways"
        )
    }

    @Test("sorting the same set twice yields the same order")
    func orderIsReproducible() {
        let produced = (0 ..< 12).map {
            suggestion(template: "predicate", score: 20, identity: "id\($0)")
        }
        let first = produced.sorted(by: SwiftInferCommand.Discover.strongestFirst)
        let second = produced.shuffled().sorted(by: SwiftInferCommand.Discover.strongestFirst)
        #expect(first.map(\.identity.normalized) == second.map(\.identity.normalized))
    }

    /// Ordering is not hiding. The rescue still surfaces the owed law; this
    /// only decides where it appears.
    @Test("a predicate is still present after sorting, just not first")
    func owedLawIsStillSurfaced() {
        let produced = [
            suggestion(template: "idempotence", score: 80, identity: "i1"),
            suggestion(template: "predicate", score: 20, identity: "p1")
        ]
        let ordered = produced.sorted(by: SwiftInferCommand.Discover.strongestFirst)
        #expect(ordered.count == 2)
        #expect(ordered.last?.templateName == "predicate")
    }
}
