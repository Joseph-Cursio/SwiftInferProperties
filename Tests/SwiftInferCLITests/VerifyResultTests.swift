import Foundation
import Testing

@testable import SwiftInferCLI

// V1.43.C/D — VerifyResultParser + VerifyResultRenderer tests for the
// 4-outcome two-pass shape (`bothPass` / `edgeCaseAdvisory` /
// `defaultFails` / `error`). Replaces v1.42's 3-outcome assertions.
// Split into two suites by responsibility to keep per-type body length
// within lint bounds.

// MARK: - Parser

@Suite("VerifyResult — V1.43.C parser (4-outcome two-pass shape)")
struct VerifyResultParserTests {

    private static func output(
        exitCode: Int32,
        stdout: String,
        stderr: String = ""
    ) -> VerifierSubprocess.Output {
        VerifierSubprocess.Output(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    // MARK: - bothPass

    @Test("parser recognizes both-pass markers + exit 0 → .bothPass(...)")
    func parsesBothPassOutcome() {
        let raw = Self.output(
            exitCode: 0,
            stdout: [
                "VERIFY_DEFAULT_RESULT: PASS",
                "VERIFY_DEFAULT_TRIALS: 100",
                "VERIFY_EDGE_RESULT: PASS",
                "VERIFY_EDGE_TRIALS: 100",
                "VERIFY_EDGE_SAMPLED: 12"
            ].joined(separator: "\n")
        )
        let outcome = VerifyResultParser.parse(raw)
        #expect(outcome == .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 12))
    }

    @Test("parser tolerates extra lines around the per-pass markers")
    func parsesBothPassOutcomeWithChatter() {
        let raw = Self.output(
            exitCode: 0,
            stdout: [
                "Building...",
                "DONE",
                "VERIFY_DEFAULT_RESULT: PASS",
                "VERIFY_DEFAULT_TRIALS: 100",
                "intermediate debug line",
                "VERIFY_EDGE_RESULT: PASS",
                "VERIFY_EDGE_TRIALS: 100",
                "VERIFY_EDGE_SAMPLED: 11",
                "bye"
            ].joined(separator: "\n")
        )
        let outcome = VerifyResultParser.parse(raw)
        #expect(outcome == .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 11))
    }

    // MARK: - edgeCaseAdvisory

    @Test("parser recognizes edge-fail + default-pass + exit 1 → .edgeCaseAdvisory(...)")
    func parsesEdgeCaseAdvisoryOutcome() {
        let raw = Self.output(
            exitCode: 1,
            stdout: [
                "VERIFY_DEFAULT_RESULT: PASS",
                "VERIFY_DEFAULT_TRIALS: 100",
                "VERIFY_EDGE_RESULT: FAIL",
                "VERIFY_EDGE_TRIAL: 7",
                "VERIFY_EDGE_INPUT: Complex(nan, 0.0)",
                "VERIFY_EDGE_FORWARD: Complex(nan, nan)",
                "VERIFY_EDGE_INVERSE: Complex(nan, nan)",
                "VERIFY_EDGE_INDEX: 1"
            ].joined(separator: "\n")
        )
        let outcome = VerifyResultParser.parse(raw)
        #expect(outcome == .edgeCaseAdvisory(
            defaultTrials: 100,
            edge: EdgeCaseDetail(
                trial: 7,
                input: "Complex(nan, 0.0)",
                forward: "Complex(nan, nan)",
                inverse: "Complex(nan, nan)",
                caseIndex: 1
            )
        ))
    }

    @Test("parser tolerates VERIFY_EDGE_INDEX: -1 (non-curated value)")
    func parsesEdgeCaseAdvisoryWithUnknownIndex() {
        let raw = Self.output(
            exitCode: 1,
            stdout: [
                "VERIFY_DEFAULT_RESULT: PASS",
                "VERIFY_DEFAULT_TRIALS: 100",
                "VERIFY_EDGE_RESULT: FAIL",
                "VERIFY_EDGE_TRIAL: 3",
                "VERIFY_EDGE_INPUT: Complex(1.5, -2.5)",
                "VERIFY_EDGE_FORWARD: Complex(3.0, -5.0)",
                "VERIFY_EDGE_INVERSE: Complex(0.0, 0.0)",
                "VERIFY_EDGE_INDEX: -1"
            ].joined(separator: "\n")
        )
        let outcome = VerifyResultParser.parse(raw)
        if case let .edgeCaseAdvisory(_, edge) = outcome {
            #expect(edge.caseIndex == -1)
        } else {
            Issue.record("expected .edgeCaseAdvisory; got \(outcome)")
        }
    }

    // MARK: - defaultFails

    @Test("parser recognizes default-fail + exit 1 → .defaultFails(...)")
    func parsesDefaultFailsOutcome() {
        let raw = Self.output(
            exitCode: 1,
            stdout: [
                "VERIFY_DEFAULT_RESULT: FAIL",
                "VERIFY_DEFAULT_TRIAL: 47",
                "VERIFY_DEFAULT_INPUT: Complex(0.0042, -1.7e6)",
                "VERIFY_DEFAULT_FORWARD: Complex(3.1, 2.2)",
                "VERIFY_DEFAULT_INVERSE: Complex(99.0, 0.0)"
            ].joined(separator: "\n")
        )
        let outcome = VerifyResultParser.parse(raw)
        #expect(outcome == .defaultFails(
            trial: 47,
            input: "Complex(0.0042, -1.7e6)",
            forwardResult: "Complex(3.1, 2.2)",
            inverseResult: "Complex(99.0, 0.0)",
            shrunk: nil,
            shrinkSteps: 0
        ))
    }

    @Test("parser captures the v1.141 shrink markers into .defaultFails")
    func parsesShrinkMarkers() {
        let raw = Self.output(
            exitCode: 1,
            stdout: [
                "VERIFY_DEFAULT_RESULT: FAIL",
                "VERIFY_DEFAULT_TRIAL: 12",
                "VERIFY_DEFAULT_INPUT: Complex(8.3e5, -2.1e5)",
                "VERIFY_DEFAULT_FORWARD: Complex(1.0, 1.0)",
                "VERIFY_DEFAULT_INVERSE: Complex(2.0, 2.0)",
                "VERIFY_DEFAULT_SHRUNK: Complex(0.0, 0.0)",
                "VERIFY_SHRINK_STEPS: 14"
            ].joined(separator: "\n")
        )
        let outcome = VerifyResultParser.parse(raw)
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails; got \(outcome)")
            return
        }
        #expect(detail.input == "Complex(8.3e5, -2.1e5)")
        #expect(detail.shrink?.minimal == "Complex(0.0, 0.0)")
        #expect(detail.shrink?.steps == 14)
    }

    // MARK: - Error

    @Test("exit code != 0 / 1 → .error(...) with stdout snippet")
    func parsesErrorOutcomeOnUnexpectedExitCode() {
        let raw = Self.output(
            exitCode: 134,
            stdout: "VERIFIER CRASHED\nstack frame\nstack frame"
        )
        let outcome = VerifyResultParser.parse(raw)
        if case let .error(reason) = outcome {
            #expect(reason.contains("134"))
            #expect(reason.contains("VERIFIER CRASHED"))
        } else {
            Issue.record("expected .error; got \(outcome)")
        }
    }

    @Test("missing per-pass markers → .error(...)")
    func parsesErrorOutcomeOnMissingMarkers() {
        let raw = Self.output(
            exitCode: 0,
            stdout: "no markers here"
        )
        let outcome = VerifyResultParser.parse(raw)
        if case .error = outcome { /* ok */ } else {
            Issue.record("expected .error; got \(outcome)")
        }
    }

    @Test("both-pass markers with non-0 exit code → .error(...) (refuses to trust)")
    func parsesErrorOnBothPassWithNonZeroExit() {
        let raw = Self.output(
            exitCode: 2,
            stdout: [
                "VERIFY_DEFAULT_RESULT: PASS",
                "VERIFY_DEFAULT_TRIALS: 100",
                "VERIFY_EDGE_RESULT: PASS",
                "VERIFY_EDGE_TRIALS: 100",
                "VERIFY_EDGE_SAMPLED: 12"
            ].joined(separator: "\n")
        )
        let outcome = VerifyResultParser.parse(raw)
        if case .error = outcome { /* ok */ } else {
            Issue.record("expected .error; got \(outcome)")
        }
    }
}
