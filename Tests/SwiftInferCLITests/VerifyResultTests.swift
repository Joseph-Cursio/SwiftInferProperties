import Foundation
import Testing

@testable import SwiftInferCLI

/// V1.42.C.4 — VerifyResultParser + VerifyResultRenderer tests.
///
/// Covers the parse-stdout-to-VerifyOutcome contract and the render-
/// to-user-string contract independently. The two modules compose:
/// the harness calls `parse(...)` on the subprocess output and feeds
/// the result into `render(_:context:)` for printing.
@Suite("VerifyResult — V1.42.C.4 parse + render")
struct VerifyResultTests {

    // MARK: - Parser fixtures

    private static func output(
        exitCode: Int32,
        stdout: String,
        stderr: String = ""
    ) -> VerifierSubprocess.Output {
        VerifierSubprocess.Output(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    // MARK: - Pass parsing

    @Test("parser recognizes PASS marker + exit 0 → .pass(trials:)")
    func parsesPassOutcome() {
        let raw = Self.output(
            exitCode: 0,
            stdout: "VERIFY_RESULT: PASS\nVERIFY_TRIALS: 100"
        )
        let outcome = VerifyResultParser.parse(raw)
        #expect(outcome == .pass(trials: 100))
    }

    @Test("parser tolerates extra lines before / after markers")
    func parsesPassOutcomeWithChatter() {
        let raw = Self.output(
            exitCode: 0,
            stdout: "Building...\nDONE\nVERIFY_RESULT: PASS\nVERIFY_TRIALS: 100\nbye"
        )
        let outcome = VerifyResultParser.parse(raw)
        #expect(outcome == .pass(trials: 100))
    }

    // MARK: - Fail parsing

    @Test("parser recognizes FAIL marker + exit 1 → .fail(...) populated from markers")
    func parsesFailOutcome() {
        let raw = Self.output(
            exitCode: 1,
            stdout: [
                "VERIFY_RESULT: FAIL",
                "VERIFY_TRIAL: 47",
                "VERIFY_INPUT: Complex(0.0042, -1.7e6)",
                "VERIFY_FORWARD: Complex(3.1, 2.2)",
                "VERIFY_INVERSE: Complex(99.0, 0.0)"
            ].joined(separator: "\n")
        )
        let outcome = VerifyResultParser.parse(raw)
        #expect(outcome == .fail(
            trial: 47,
            input: "Complex(0.0042, -1.7e6)",
            forwardResult: "Complex(3.1, 2.2)",
            inverseResult: "Complex(99.0, 0.0)"
        ))
    }

    // MARK: - Error parsing

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

    @Test("missing PASS / FAIL markers → .error(...)")
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

    @Test("PASS marker with non-0 exit code → .error(...) (refuses to trust)")
    func parsesErrorOnPassWithNonZeroExit() {
        let raw = Self.output(
            exitCode: 2,
            stdout: "VERIFY_RESULT: PASS\nVERIFY_TRIALS: 100"
        )
        let outcome = VerifyResultParser.parse(raw)
        if case .error = outcome { /* ok */ } else {
            Issue.record("expected .error; got \(outcome)")
        }
    }

    // MARK: - Renderer

    private static let canonicalContext = VerifyResultRenderer.Context(
        forwardName: "Complex.exp",
        inverseName: "Complex.log",
        carrierType: "Complex<Double>"
    )

    @Test("pass renders as a single ✓ line")
    func rendersPass() {
        let rendered = VerifyResultRenderer.render(
            .pass(trials: 100),
            context: Self.canonicalContext
        )
        #expect(rendered.hasPrefix("✓ verify holds"))
        #expect(rendered.contains("Complex.exp/Complex.log"))
        #expect(rendered.contains("Complex<Double>"))
        #expect(rendered.contains("100 trials"))
    }

    @Test("pass with N=1 uses singular 'trial'")
    func rendersPassSingular() {
        let rendered = VerifyResultRenderer.render(
            .pass(trials: 1),
            context: Self.canonicalContext
        )
        #expect(rendered.contains("1 trial,"))
        #expect(!rendered.contains("1 trials"))
    }

    @Test("fail renders ✗ header + 4 counterexample rows")
    func rendersFail() {
        let rendered = VerifyResultRenderer.render(
            .fail(
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
        #expect(rendered.contains("trial 47"))
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

    @Test("end-to-end: pass-shaped stdout → pass outcome → ✓ rendering")
    func endToEndPass() {
        let raw = Self.output(
            exitCode: 0,
            stdout: "VERIFY_RESULT: PASS\nVERIFY_TRIALS: 100"
        )
        let outcome = VerifyResultParser.parse(raw)
        let rendered = VerifyResultRenderer.render(outcome, context: Self.canonicalContext)
        #expect(rendered.hasPrefix("✓ verify holds"))
    }
}
