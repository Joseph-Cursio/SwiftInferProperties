import Foundation
import PropertyLawKit
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// Split from `MergeAlgebraPropertyTests.swift` to keep that file under the
// `file_length` / `type_body_length` caps. The seam is meaningful rather than
// arbitrary: that file holds the laws `merge` **satisfies**, this one holds the
// law it does not — the commutativity `discover` proposed at the same tier as
// associativity, refuted here over a controlled clock.
extension MergeAlgebraPropertyTests {

    // MARK: - The law that does NOT hold, stated over the clock

    /// **Commutativity is false, and the injected clock is what states it
    /// properly.**
    ///
    /// The property below quantifies over pairs of clock readings and asserts
    /// the exact biconditional: `merge` commutes **iff** the two records were
    /// stamped at different readings. When the clock reads the same value twice
    /// — one whole second, two writes, which is precisely what `.iso8601`
    /// persistence collapses distinct sub-second instants into — the fold's `>=`
    /// keeps the *receiver's* record and the two orders disagree.
    ///
    /// The first version of this suite could only assert the one-directional
    /// half at a hand-picked literal. Driving the production builder from a
    /// controlled clock is what turns "here is a counterexample" into "here is
    /// exactly when it happens."
    @Test("merge commutes iff the clock readings differ")
    func mergeCommutesIffReadingsDiffer() async {
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

            let commutes = left.merge(right) == right.merge(left)
            #expect(
                commutes == (firstReading != secondReading),
                "merge must commute exactly when the two stamps differ"
            )
            if firstReading == secondReading {
                // …and on a tie, the receiver is what survives.
                #expect(left.merge(right).records == [accepted])
                #expect(right.merge(left).records == [rejected])
            }
        }
    }

    /// The same biconditional on the evidence log, through *its* production
    /// builder — so the finding is pinned as a property of the fold shape, not
    /// of one carrier.
    @Test("VerifyEvidenceLog.merge commutes iff the clock readings differ")
    func evidenceMergeCommutesIffReadingsDiffer() async {
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
            #expect((left.merge(right) == right.merge(left)) == (firstReading != secondReading))

            // **Which record survives, not merely that the two orders differ.**
            // Mutation testing caught this omission: flipping the fold's `>=` to
            // `>` makes the tie *last*-seen-wins instead of first, which is still
            // non-commutative — so the biconditional above passes unchanged and
            // the mutant survived. Naming the survivor is what distinguishes the
            // two tie-break policies, and it is the difference between "these
            // disagree" and "these disagree in this specific way."
            if firstReading == secondReading {
                #expect(left.merge(right).records == [passed], "receiver must win the tie")
                #expect(right.merge(left).records == [failed])
            }
        }
    }
}
