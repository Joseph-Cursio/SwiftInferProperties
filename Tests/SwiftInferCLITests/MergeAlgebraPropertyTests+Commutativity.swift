import Foundation
import PropertyLawKit
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// Split from `MergeAlgebraPropertyTests.swift` to keep that file under the
// `file_length` / `type_body_length` caps.
//
// **This file used to hold the law `merge` did NOT satisfy.** From v1.4.1 until
// 2026-08-05 the four folds were non-commutative, and these tests pinned that as
// known drift: `merge` commuted *iff* the two clock readings differed, and on a
// tie the receiver's record survived. The seam between the two files was
// "laws it satisfies" vs "the law it does not."
//
// The drift is fixed (`IdentityKeyedFold`), so these now assert commutativity
// as a law like any other. The file stays separate for the size cap and for the
// history below, which is the part worth not losing.
//
// **What the clock injection bought, and why it still matters.** The first
// version of this suite built records by hand at literal instants, because the
// production code stamped them with an un-injectable `Date()` — a test-side
// workaround for a source-side problem that SwiftProjectLint's
// `Non-Injected Nondeterminism` rule had already flagged (§12). With the clock
// injected, every record is built by the **production builder**
// (`InteractiveTriage.makeRecord`, `ViewModelVerifyEvidence.evidence`) at an
// instant this suite chooses, so the laws cover the builders and not just the
// folds. The tie that used to refute commutativity is produced by *the clock
// reading twice the same* — what actually happens when two records are written
// inside one whole second and persisted at `.iso8601` resolution — rather than
// by a literal chosen to make the point. That tie is now the interesting case
// for the opposite reason: it is where commutativity is hardest to hold.
//
// **The mutation-testing lesson, preserved because it still binds.** Flipping
// the old fold's `>=` to `>` changed the tie from first-seen-wins to
// last-seen-wins — still non-commutative — and the biconditional passed
// unchanged, so the mutant survived. Asserting only "the two orders agree" is
// weak in the mirror-image way: a tie-break that *fabricated* a record, or that
// dropped the timestamp entirely, would satisfy it. So the arms below also pin
// that the survivor is one of the two inputs, that exactly one record comes
// back, and that a later stamp still wins.
extension MergeAlgebraPropertyTests {

    // MARK: - Commutativity, over every pair of clock readings

    /// **`merge` commutes, including when the clock reads the same value twice.**
    ///
    /// The equal-reading case is the one that used to fail. `IdentityKeyedFold`
    /// breaks a `timestamp` tie by the records' canonical encoding rather than
    /// by which side of `merge` they arrived on, so the result no longer depends
    /// on argument order.
    @Test("merge commutes for every pair of clock readings")
    func mergeCommutesForEveryReadingPair() async {
        await propertyCheck(
            input: Gen.element(of: Self.readings).map { $0! },
            Gen.element(of: Self.readings).map { $0! }
        ) { firstReading, secondReading in
            // One identity, two different verdicts, stamped by the clock.
            let identity = Self.identities[0]
            let accepted = InteractiveTriage.makeRecord(
                for: Self.suggestion(identity),
                decision: .accepted,
                timestamp: firstReading
            )
            let rejected = InteractiveTriage.makeRecord(
                for: Self.suggestion(identity),
                decision: .rejected,
                timestamp: secondReading
            )
            let left = Decisions(records: [accepted])
            let right = Decisions(records: [rejected])

            #expect(
                left.merge(right) == right.merge(left),
                "merge must commute at every pair of stamps, ties included"
            )
            if firstReading == secondReading {
                // The tie arm, pinned against a fabricating tie-break: exactly
                // one record survives and it is one of the two that went in.
                let survivors = left.merge(right).records
                #expect(survivors.count == 1)
                #expect(survivors == [accepted] || survivors == [rejected])
            }
        }
    }

    /// The same law on the evidence log, through *its* production builder — so
    /// commutativity is pinned as a property of the shared fold shape rather
    /// than of one carrier. All four logs route through `IdentityKeyedFold`.
    @Test("VerifyEvidenceLog.merge commutes for every pair of clock readings")
    func evidenceMergeCommutesForEveryReadingPair() async {
        await propertyCheck(
            input: Gen.element(of: Self.readings).map { $0! },
            Gen.element(of: Self.readings).map { $0! }
        ) { firstReading, secondReading in
            let identity = Self.identities[0]
            let passed = ViewModelVerifyEvidence.evidence(
                for: Self.interactionSuggestion(identity),
                outcome: .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
                now: firstReading
            )
            let failed = ViewModelVerifyEvidence.evidence(
                for: Self.interactionSuggestion(identity),
                outcome: .defaultFails(
                    DefaultFailDetail(trial: 1, input: "x", forwardResult: "a", inverseResult: "b")
                ),
                now: secondReading
            )
            let left = VerifyEvidenceLog(records: [passed])
            let right = VerifyEvidenceLog(records: [failed])
            #expect(left.merge(right) == right.merge(left))

            if firstReading == secondReading {
                let survivors = left.merge(right).records
                #expect(survivors.count == 1)
                #expect(survivors == [passed] || survivors == [failed])
            }
        }
    }

    /// Recency must still decide when the stamps differ. Commutativity is easy
    /// to get by throwing the timestamp away — this is the arm that stops that,
    /// and it is why the fix ranks by `(timestamp, canonical)` rather than by
    /// the encoding alone.
    @Test("the later stamp still wins, from either argument position")
    func laterStampStillWins() {
        let identity = Self.identities[0]
        let earlier = InteractiveTriage.makeRecord(
            for: Self.suggestion(identity),
            decision: .accepted,
            timestamp: Self.readings[0]
        )
        let later = InteractiveTriage.makeRecord(
            for: Self.suggestion(identity),
            decision: .rejected,
            timestamp: Self.readings[2]
        )
        let earlierFirst = Decisions(records: [earlier]).merge(Decisions(records: [later]))
        let laterFirst = Decisions(records: [later]).merge(Decisions(records: [earlier]))
        #expect(earlierFirst.records == [later])
        #expect(laterFirst.records == [later])
    }
}
