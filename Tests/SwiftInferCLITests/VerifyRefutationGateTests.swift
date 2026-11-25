import ArgumentParser
import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `verify --fail-on-refutation` — the opt-in CI gate, in both modes.
///
/// **Refuted means a counterexample was found**: the primary law's `.defaultFails`, or a
/// companion law that refutes. Errors, declines (`not-a-candidate`, recorded as
/// `architectural-coverage-pending`), skipped entries and edge-case advisories must not trip it,
/// and without the flag nothing trips it — verify's exit status is what it was before the flag.
/// The end-to-end arm, which drives the command against a real build, is
/// `NamespaceRoundTripVerifyMeasuredTests`.
@Suite("verify --fail-on-refutation — exit only on a found counterexample")
struct VerifyRefutationGateTests {

    private typealias Verify = SwiftInferCommand.Verify

    private static let counterexample = VerifyOutcome.defaultFails(
        DefaultFailDetail(trial: 0, input: "\"a b\"", forwardResult: "\"a%20b\"", inverseResult: "\"a%20b\"")
    )

    private static let nonRefutations: [VerifyOutcome] = [
        .bothPass(defaultTrials: 1_000, edgeTrials: 100, edgeSampled: 4),
        .edgeCaseAdvisory(
            defaultTrials: 1_000,
            edge: EdgeCaseDetail(trial: 3, input: "nan", forward: "nan", inverse: "nan", caseIndex: 2)
        ),
        .error(reason: "build-failed"),
    ]

    private static func run(_ outcome: VerifyOutcome, companions: [CompanionLawOutcome] = []) -> Verify.VerifyRun {
        Verify.VerifyRun(outcome: outcome, rendered: "", companionLaws: companions)
    }

    private static func record(
        _ outcome: Verify.SurveyOutcome,
        detail: String? = nil,
        companions: [CompanionLawOutcome]? = nil
    ) -> Verify.SurveyRecord {
        var record = Verify.SurveyRecord(
            identityHash: "0x3184A52016D53F64",
            templateName: "round-trip",
            primaryFunctionName: "encode(_:)",
            carrier: "Slug",
            outcome: outcome,
            outcomeDetail: detail
        )
        record.companionLaws = companions
        return record
    }

    // MARK: - The flag

    @Test("--fail-on-refutation is off by default and parses in both modes")
    func flagParses() throws {
        #expect(try Verify.parse(["--suggestion", "abc123"]).failOnRefutation == false)
        #expect(try Verify.parse(["--suggestion", "abc123", "--fail-on-refutation"]).failOnRefutation)
        #expect(try Verify.parse(["--all-from-index", "--fail-on-refutation"]).failOnRefutation)
    }

    // MARK: - --suggestion

    @Test("--suggestion: a counterexample trips the gate")
    func suggestionCounterexampleFails() {
        #expect(Verify.failsRefutationGate(enabled: true, run: Self.run(Self.counterexample)))
    }

    @Test("--suggestion: a pass, an edge-case advisory or an error does not")
    func suggestionNonRefutationsPass() {
        for outcome in Self.nonRefutations {
            #expect(!Verify.failsRefutationGate(enabled: true, run: Self.run(outcome)), "\(outcome)")
        }
    }

    /// A companion law (#711) that fails is a counterexample the stub found, and
    /// `CompanionLawOutcome.refutes` is how the evidence log reads it.
    @Test("--suggestion: a refuting companion law trips the gate on a passing primary law")
    func suggestionCompanionRefutationFails() {
        let passing = Self.nonRefutations[0]
        let failed = CompanionLawOutcome(law: "C1", status: .failed, trial: 2, input: "[1]", output: "[]")
        let held = CompanionLawOutcome(law: "C2", status: .held)
        #expect(Verify.failsRefutationGate(enabled: true, run: Self.run(passing, companions: [held, failed])))
        #expect(!Verify.failsRefutationGate(enabled: true, run: Self.run(passing, companions: [held])))
    }

    @Test("--suggestion without the flag: a counterexample does not change the exit")
    func suggestionWithoutFlagNeverFails() {
        #expect(!Verify.failsRefutationGate(enabled: false, run: Self.run(Self.counterexample)))
    }

    // MARK: - --all-from-index

    @Test("--all-from-index: one refuted record among others trips the gate")
    func surveyCounterexampleFails() {
        let records = [
            Self.record(.measuredBothPass),
            Self.record(.measuredDefaultFails, detail: "trial=0"),
            Self.record(.measuredError, detail: "timed-out: 600s"),
        ]
        #expect(Verify.failsRefutationGate(enabled: true, records: records))
    }

    /// The outcomes the user ruled out: errors, declines (every `not-a-candidate` is recorded as
    /// `architectural-coverage-pending`), and skipped entries, which leave no record. The edge
    /// pass is advisory by design and cannot retract the default pass's verdict.
    @Test("--all-from-index: errors, declines, advisories and an empty survey do not")
    func surveyNonRefutationsPass() {
        let records = [
            Self.record(.measuredBothPass),
            Self.record(.measuredEdgeCaseAdvisory),
            Self.record(.measuredError, detail: "exception: boom"),
            Self.record(
                .architecturalCoveragePending,
                detail: "not-a-candidate: carrier `SamplingSeed` is a caseless enum"
            ),
            Self.record(.architecturalCoveragePending, detail: "unsupported-template: sorted-output"),
        ]
        #expect(!Verify.failsRefutationGate(enabled: true, records: records))
        #expect(!Verify.failsRefutationGate(enabled: true, records: []))
    }

    @Test("--all-from-index: a refuting companion law trips the gate")
    func surveyCompanionRefutationFails() {
        let trapped = CompanionLawOutcome(law: "C2", status: .trapped)
        #expect(Verify.failsRefutationGate(
            enabled: true, records: [Self.record(.measuredBothPass, companions: [trapped])]
        ))
    }

    @Test("--all-from-index without the flag: refuted records do not change the exit")
    func surveyWithoutFlagNeverFails() {
        let records = [Self.record(.measuredDefaultFails, detail: "trial=0")]
        #expect(!Verify.failsRefutationGate(enabled: false, records: records))
    }
}
