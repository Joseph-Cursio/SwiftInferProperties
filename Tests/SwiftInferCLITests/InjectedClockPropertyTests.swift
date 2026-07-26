import Foundation
import PropertyLawKit
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// Self-dogfood road test (`docs/roadtest-self-dogfood.md` §12) — the stage of
// the loop I skipped, run late.
//
// SwiftProjectLint's `Non-Injected Nondeterminism` rule fired 18 times on this
// repo with one message: *"`Date()` makes this code unpredictable, so a
// property-based test can't pin the value or reproduce a failure. Inject the
// source (a clock `() -> Date`, …) so tests can control it."* Six of those sites
// stamp `VerifyEvidence.capturedAt` / `VerifyCorpusEntry.capturedAt` — the very
// fields whose ties make the persistence-log `merge` folds non-commutative
// (`MergeAlgebraPropertyTests`). The linter named the cause in stage one; the
// road test rediscovered the consequence by hand in stage three.
//
// The sites now take `now: Date = Date()`. **A defaulted parameter is not an
// injection until something passes it** — a signature change alone is
// indistinguishable from the bug it claims to fix. These tests pass it, and
// assert the stamp is the value handed in and nothing else.
//
// Note what this buys beyond tidiness. `MergeAlgebraPropertyTests` reaches the
// tie case by hand-narrowing its generator to a two-value instant alphabet —
// the *test-side* workaround for the *source-side* problem. With the clock
// injected, evidence records can be built at chosen instants directly, so a
// future merge law can be stated over a controlled clock instead of a rigged
// generator.
@Suite("Road test — injected clocks actually control the persisted stamp")
struct InjectedClockPropertyTests {

    /// The four `VerifyOutcome` arms with minimal payloads. Every arm is
    /// exercised so no branch of the mapping switch can quietly reach for the
    /// wall clock on its own.
    private static let outcomes: [VerifyOutcome] = [
        .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
        .defaultFails(DefaultFailDetail(trial: 1, input: "x", forwardResult: "a", inverseResult: "b")),
        .edgeCaseAdvisory(
            defaultTrials: 100,
            edge: EdgeCaseDetail(trial: 1, input: "x", forward: "a", inverse: "b", caseIndex: 0)
        ),
        .error(reason: "boom")
    ]

    private static let instants = [
        Date(timeIntervalSince1970: 0),
        Date(timeIntervalSince1970: 1_000_000),
        Date(timeIntervalSince1970: 1_774_000_000)
    ]

    private static func suggestion(
        _ family: InteractionInvariantFamily = .idempotence
    ) -> InteractionInvariantSuggestion {
        InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: "\(family.rawValue)::Feature.reduce::p"),
            family: family,
            reducerQualifiedName: "Feature.reduce",
            reducerLocation: "Feature.swift:1",
            stateTypeName: "State",
            actionTypeName: "Action",
            predicate: "p",
            score: 40,
            tier: .likely,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// The MVVM evidence builder stamps exactly the instant it is given — for
    /// every outcome, so no arm reaches for the wall clock on its own.
    @Test("ViewModelVerifyEvidence stamps the injected instant, every outcome")
    func viewModelEvidenceUsesInjectedClock() async {
        await propertyCheck(
            input: Gen.element(of: Self.instants).map { $0! },
            Gen.element(of: Self.outcomes).map { $0! }
        ) { instant, outcome in
            let evidence = ViewModelVerifyEvidence.evidence(
                for: Self.suggestion(),
                outcome: outcome,
                now: instant
            )
            #expect(evidence.capturedAt == instant)
        }
    }

    @Test("OutputDeterminismVerifyEvidence stamps the injected instant, every outcome")
    func outputDeterminismEvidenceUsesInjectedClock() async {
        await propertyCheck(
            input: Gen.element(of: Self.instants).map { $0! },
            Gen.element(of: Self.outcomes).map { $0! }
        ) { instant, outcome in
            let evidence = OutputDeterminismVerifyEvidence.evidence(
                for: Self.suggestion(),
                outcome: outcome,
                now: instant
            )
            #expect(evidence.capturedAt == instant)
        }
    }

    /// The reducer-path builder, across every family and every parsed outcome.
    @Test("VerifyInteractionPipeline.makeEvidence stamps the injected instant")
    func interactionEvidenceUsesInjectedClock() async {
        await propertyCheck(
            input: Gen.element(of: Self.instants).map { $0! },
            Gen.element(of: VerifyEvidenceOutcome.allCases).map { $0! },
            Gen.element(of: InteractionInvariantFamily.allCases).map { $0! }
        ) { instant, outcome, family in
            let evidence = VerifyInteractionPipeline.makeEvidence(
                invariant: Self.suggestion(family),
                result: .init(outcome: outcome, detail: nil, excludedActionCount: 0),
                now: instant
            )
            #expect(evidence.capturedAt == instant)
        }
    }

    /// **The property the injection exists for.** Two evidence records built at
    /// *the same* injected instant tie exactly — which is the precondition
    /// `MergeAlgebraPropertyTests` had to manufacture with a narrowed generator.
    /// Built at *different* instants they order strictly. Stating both directions
    /// is what makes this a control on the clock rather than a restatement of
    /// the assignment above.
    @Test("an injected clock makes ties reachable and ordering exact")
    func injectedClockControlsTiesAndOrdering() async {
        await propertyCheck(
            input: Gen.element(of: Self.instants).map { $0! },
            Gen.element(of: Self.instants).map { $0! }
        ) { first, second in
            let lhs = ViewModelVerifyEvidence.evidence(
                for: Self.suggestion(),
                outcome: .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
                now: first
            )
            let rhs = ViewModelVerifyEvidence.evidence(
                for: Self.suggestion(),
                outcome: .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
                now: second
            )
            #expect((lhs.capturedAt == rhs.capturedAt) == (first == second))
            #expect((lhs.capturedAt < rhs.capturedAt) == (first < second))
        }
    }

    /// The default argument still reads the wall clock — the injection must not
    /// have frozen production behaviour. Bounded rather than exact, since the
    /// wall clock is precisely the thing that cannot be pinned.
    @Test("omitting the argument still stamps the wall clock")
    func defaultArgumentStillUsesWallClock() {
        let before = Date()
        let evidence = ViewModelVerifyEvidence.evidence(
            for: Self.suggestion(),
            outcome: .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0)
        )
        let after = Date()
        #expect(evidence.capturedAt >= before)
        #expect(evidence.capturedAt <= after)
    }
}
