import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `discover` has always SAID a private subject's law cannot run — as prose, in a caveat
/// nothing downstream could key on. `verify` then built the stub anyway and filed the
/// result as `build-failed`, an instrument-failure bucket for a fact known before the
/// build started.
@Suite("subjectNotVisibleToTests — saying it as a signal, not only as prose")
struct SubjectNotVisibleBlockerTests {

    /// The two restrictions no test can work around.
    @Test(
        "a private subject blocks every test",
        arguments: [AccessRestriction.notVisibleToTests, .enclosingTypeNotVisibleToTests]
    )
    func privateSubjectsBlock(restriction: AccessRestriction) {
        #expect(SwiftInferCommand.Discover.blocksEveryTest(restriction))
    }

    /// **The arm that protects working rows.** `@testable` promotes `internal`, so blocking
    /// `.internalOrSPI` would silently stop verifying laws that pass today.
    @Test(
        "internal and nested-local do NOT block",
        arguments: [AccessRestriction.internalOrSPI, .nestedLocal]
    )
    func reachableRestrictionsDoNotBlock(restriction: AccessRestriction) {
        #expect(!SwiftInferCommand.Discover.blocksEveryTest(restriction))
    }

    /// The signal has to reach `StructuralBlocker`, or the emission is decoration.
    @Test("the signal is a structural blocker and carries its own detail")
    func signalIsAStructuralBlocker() {
        let signal = Signal(
            kind: .subjectNotVisibleToTests,
            weight: 0,
            detail: "no test can name the subject: make it internal"
        )
        #expect(StructuralBlocker.reason(among: [signal]) == signal.detail)
    }

    /// **Score-neutral by construction.** §2's remedy is to lift the law to a reachable
    /// caller; demoting the row would hide the advice the row exists to give.
    @Test("the signal carries zero weight, so tiers do not move")
    func signalIsScoreNeutral() {
        let score = Score(advisorySignals: [
            Signal(kind: .subjectNotVisibleToTests, weight: 0, detail: "x")
        ])
        #expect(score.total == 0)
    }

    /// An unrelated signal must not be read as a blocker.
    @Test("an ordinary signal is not a structural blocker")
    func ordinarySignalIsNotABlocker() {
        let signal = Signal(kind: .typeSymmetrySignature, weight: 30, detail: "T -> T")
        #expect(StructuralBlocker.reason(among: [signal]) == nil)
    }
}
