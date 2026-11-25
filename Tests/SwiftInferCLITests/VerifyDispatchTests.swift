import ArgumentParser
import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `verify`'s dispatch, with the pipeline and survey stubbed out: a parsed flag reaches the
/// runner, and `--fail-on-refutation` reads what the runner returned.
///
/// `VerifyRefutationGateTests` and `SuggestionPersistOptOutTests` test the gate's rule and
/// `persistSingleRun` in isolation, and both stay green when the command never calls them (the
/// original `--no-persist-evidence` bug was exactly that: the flag was parsed and not forwarded).
/// These close that gap in the fast suite. The build-backed arm is
/// `NamespaceRoundTripVerifyMeasuredTests`.
@Suite("verify dispatch — flags reach the runners, the gate reads their result")
struct VerifyDispatchTests {

    private typealias Verify = SwiftInferCommand.Verify

    /// Captures what `execute` handed each runner and returns a canned result.
    private final class Recorder {
        var suggestionRequests: [Verify.SuggestionRequest] = []
        var surveyRequests: [Verify.SurveyRequest] = []
        let run: Verify.VerifyRun
        let records: [Verify.SurveyRecord]

        init(
            run: Verify.VerifyRun = Recorder.verifyRun(.bothPass(defaultTrials: 1, edgeTrials: 0, edgeSampled: 0)),
            records: [Verify.SurveyRecord] = []
        ) {
            self.run = run
            self.records = records
        }

        var runners: Verify.Runners {
            Verify.Runners(
                suggestion: { request in
                    self.suggestionRequests.append(request)
                    return self.run
                },
                survey: { request in
                    self.surveyRequests.append(request)
                    return self.records
                }
            )
        }

        static func verifyRun(
            _ outcome: VerifyOutcome, companions: [CompanionLawOutcome] = []
        ) -> Verify.VerifyRun {
            Verify.VerifyRun(outcome: outcome, rendered: "", companionLaws: companions)
        }
    }

    private static let workingDirectory = URL(fileURLWithPath: "/nonexistent/verify-dispatch")

    private static let counterexample = VerifyOutcome.defaultFails(
        trial: 0, input: "\"- - \"", forwardResult: "\"-\"", inverseResult: "\"-\""
    )

    private static func record(_ outcome: Verify.SurveyOutcome, detail: String? = nil) -> Verify.SurveyRecord {
        Verify.SurveyRecord(
            identityHash: "0x3184A52016D53F64",
            templateName: "round-trip",
            primaryFunctionName: "encode(_:)",
            carrier: "Slug",
            outcome: outcome,
            outcomeDetail: detail
        )
    }

    private func execute(_ arguments: [String], _ recorder: Recorder) throws {
        try Verify.parse(arguments).execute(workingDirectory: Self.workingDirectory, runners: recorder.runners)
    }

    // MARK: - --no-persist-evidence reaches the runner

    @Test("--suggestion forwards --no-persist-evidence as persistEvidence: false")
    func suggestionForwardsPersistOptOut() throws {
        let recorder = Recorder()
        try execute(["--suggestion", "3184A520", "--no-persist-evidence"], recorder)
        try execute(["--suggestion", "3184A520"], recorder)
        #expect(recorder.suggestionRequests.map(\.persistEvidence) == [false, true])
        #expect(recorder.suggestionRequests.first?.suggestionPrefix == "3184A520")
        #expect(recorder.suggestionRequests.first?.workingDirectory == Self.workingDirectory)
        #expect(recorder.surveyRequests.isEmpty)
    }

    @Test("--all-from-index forwards --no-persist-evidence and --template")
    func surveyForwardsPersistOptOut() throws {
        let recorder = Recorder()
        try execute(["--all-from-index", "--template", "round-trip", "--no-persist-evidence"], recorder)
        try execute(["--all-from-index"], recorder)
        #expect(recorder.surveyRequests.map(\.persistEvidence) == [false, true])
        #expect(recorder.surveyRequests.map(\.templateFilter) == ["round-trip", nil])
        #expect(recorder.suggestionRequests.isEmpty)
    }

    // MARK: - --fail-on-refutation reads the runner's result

    @Test("--suggestion: a counterexample exits non-zero only under --fail-on-refutation")
    func suggestionGate() throws {
        let recorder = Recorder(run: Recorder.verifyRun(Self.counterexample))
        #expect(throws: ExitCode.self) {
            try execute(["--suggestion", "3184A520", "--fail-on-refutation"], recorder)
        }
        try execute(["--suggestion", "3184A520"], recorder)
    }

    @Test("--suggestion: a refuting companion law exits non-zero under --fail-on-refutation")
    func suggestionCompanionGate() throws {
        let failed = CompanionLawOutcome(law: "C1", status: .failed, trial: 2, input: "[1]", output: "[]")
        let recorder = Recorder(run: Recorder.verifyRun(
            .bothPass(defaultTrials: 1, edgeTrials: 0, edgeSampled: 0), companions: [failed]
        ))
        #expect(throws: ExitCode.self) {
            try execute(["--suggestion", "3184A520", "--fail-on-refutation"], recorder)
        }
    }

    @Test("--suggestion: an error does not exit non-zero under --fail-on-refutation")
    func suggestionErrorPasses() throws {
        let recorder = Recorder(run: Recorder.verifyRun(.error(reason: "build-failed")))
        try execute(["--suggestion", "3184A520", "--fail-on-refutation"], recorder)
    }

    @Test("--all-from-index: a refuted record exits non-zero only under --fail-on-refutation")
    func surveyGate() throws {
        let recorder = Recorder(records: [
            Self.record(.measuredBothPass),
            Self.record(.measuredDefaultFails, detail: "trial=0"),
        ])
        #expect(throws: ExitCode.self) {
            try execute(["--all-from-index", "--fail-on-refutation"], recorder)
        }
        try execute(["--all-from-index"], recorder)
    }

    @Test("--all-from-index: declines and errors do not exit non-zero under --fail-on-refutation")
    func surveyDeclinesPass() throws {
        let recorder = Recorder(records: [
            Self.record(.architecturalCoveragePending, detail: "not-a-candidate: carrier `Slug` is a caseless enum"),
            Self.record(.measuredError, detail: "build-failed"),
        ])
        try execute(["--all-from-index", "--fail-on-refutation"], recorder)
    }
}
