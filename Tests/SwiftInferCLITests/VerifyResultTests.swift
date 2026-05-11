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
            edgeTrial: 7,
            edgeInput: "Complex(nan, 0.0)",
            edgeForward: "Complex(nan, nan)",
            edgeInverse: "Complex(nan, nan)",
            edgeCaseIndex: 1
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
        if case let .edgeCaseAdvisory(_, _, _, _, _, edgeCaseIndex) = outcome {
            #expect(edgeCaseIndex == -1)
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
            inverseResult: "Complex(99.0, 0.0)"
        ))
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

// MARK: - Renderer

@Suite("VerifyResult — V1.43.D renderer (4-outcome two-pass shape)")
struct VerifyResultRendererTests {

    private static let canonicalContext = VerifyResultRenderer.Context(
        forwardName: "Complex.exp",
        inverseName: "Complex.log",
        carrierType: "Complex<Double>"
    )

    private static func output(
        exitCode: Int32,
        stdout: String,
        stderr: String = ""
    ) -> VerifierSubprocess.Output {
        VerifierSubprocess.Output(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    @Test("bothPass renders ✓ strong header + per-pass counts + sampled line")
    func rendersBothPass() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 12),
            context: Self.canonicalContext
        )
        #expect(rendered.contains("✓ verify holds (strong)"))
        #expect(rendered.contains("Complex.exp/Complex.log"))
        #expect(rendered.contains("Complex<Double>"))
        #expect(rendered.contains("100 default trials"))
        #expect(rendered.contains("100 edge-case-biased trials"))
        #expect(rendered.contains("12 / 12 curated edge cases sampled"))
    }

    @Test("bothPass with N=1 uses singular 'trial'")
    func rendersBothPassSingular() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 1, edgeTrials: 1, edgeSampled: 0),
            context: Self.canonicalContext
        )
        #expect(rendered.contains("1 default trial "))
        #expect(rendered.contains("1 edge-case-biased trial,"))
        #expect(!rendered.contains("1 default trials"))
    }

    @Test("edgeCaseAdvisory with known index renders #N (label) tag")
    func rendersEdgeCaseAdvisoryKnownIndex() {
        let rendered = VerifyResultRenderer.render(
            .edgeCaseAdvisory(
                defaultTrials: 100,
                edgeTrial: 7,
                edgeInput: "Complex(nan, 0.0)",
                edgeForward: "Complex(nan, nan)",
                edgeInverse: "Complex(nan, nan)",
                edgeCaseIndex: 1
            ),
            context: Self.canonicalContext
        )
        #expect(rendered.hasPrefix("⚠ verify holds for finite domain"))
        #expect(rendered.contains("default pass 100/100"))
        #expect(rendered.contains("edge pass failed at trial 7"))
        #expect(rendered.contains("edge case #1 (Complex(NaN, 0))"))
        #expect(rendered.contains("Complex(nan, 0.0)"))
        #expect(rendered.contains("isApproximatelyEqual"))
    }

    @Test("edgeCaseAdvisory with index -1 falls back to non-curated phrasing")
    func rendersEdgeCaseAdvisoryUnknownIndex() {
        let rendered = VerifyResultRenderer.render(
            .edgeCaseAdvisory(
                defaultTrials: 100,
                edgeTrial: 3,
                edgeInput: "Complex(1.5, -2.5)",
                edgeForward: "Complex(3.0, -5.0)",
                edgeInverse: "Complex(0.0, 0.0)",
                edgeCaseIndex: -1
            ),
            context: Self.canonicalContext
        )
        #expect(rendered.contains("on a non-curated value"))
        #expect(!rendered.contains("edge case #"))
    }

    @Test("defaultFails renders ✗ header + 5 lines + (default pass) tag")
    func rendersDefaultFails() {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(
                trial: 47,
                input: "Complex(0.0042, -1.7e6)",
                forwardResult: "Complex(3.1, 2.2)",
                inverseResult: "Complex(99.0, 0.0)"
            ),
            context: Self.canonicalContext
        )
        let lines = rendered.split(separator: "\n")
        #expect(lines.count == 5)
        #expect(lines[0].hasPrefix("✗ verify fails"))
        #expect(rendered.contains("trial 47 (default pass)"))
        #expect(rendered.contains("Complex(0.0042, -1.7e6)"))
        #expect(rendered.contains("isApproximatelyEqual"))
    }

    @Test("error renders ! line with the supplied reason")
    func rendersError() {
        let rendered = VerifyResultRenderer.render(
            .error(reason: "binary crashed: SIGABRT"),
            context: Self.canonicalContext
        )
        #expect(rendered.hasPrefix("! verify error"))
        #expect(rendered.contains("SIGABRT"))
    }

    // MARK: - Round trip

    @Test("end-to-end: both-pass stdout → bothPass outcome → ✓ rendering")
    func endToEndBothPass() {
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
        let rendered = VerifyResultRenderer.render(outcome, context: Self.canonicalContext)
        #expect(rendered.hasPrefix("✓ verify holds (strong)"))
    }
}
