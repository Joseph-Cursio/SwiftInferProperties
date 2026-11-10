import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

// MARK: - V1.52.D.3 — Stderr capture in parse-error detail

@Suite("V1.52.B — Stderr capture in VerifyResultParser parse-error path")
struct V152StderrCaptureTests {

    private static func output(
        exitCode: Int32,
        stdout: String = "",
        stderr: String = ""
    ) -> VerifierSubprocess.Output {
        VerifierSubprocess.Output(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    @Test("parse-error with non-empty stderr surfaces stderr in the detail string")
    func parseErrorIncludesStderrWhenPresent() {
        // Cycle-48 evidence: subprocess exit 6 SIGABRT with empty
        // stdout; the Swift-runtime trap reason ends up on stderr.
        let raw = Self.output(
            exitCode: 6,
            stdout: "",
            stderr: "Fatal error: NaN encountered in normalization\n"
                + "Stack dump:\nFrame 0: SwiftInferVerifier.main"
        )
        guard case let .error(reason) = VerifyResultParser.parse(raw) else {
            Issue.record("expected .error outcome")
            return
        }
        // Exit 6 is SIGABRT, so this now routes through the trap diagnosis:
        // a signal-terminated run is not a refutation, and the runtime's own
        // message is quoted rather than a positional stderr tail.
        #expect(reason.contains("signal 6"))
        #expect(reason.contains("neither confirmed nor refuted"))
        #expect(reason.contains("Fatal error: NaN encountered in normalization"))
    }

    @Test("parse-error with empty stderr preserves pre-V1.52.B detail format")
    func parseErrorOmitsStderrWhenEmpty() {
        // When stderr is empty, the detail string should not include
        // a stderr segment — backward-compatible with v1.51 formatting.
        let raw = Self.output(
            exitCode: 2,
            stdout: "Some output\nVERIFY_DEFAULT_RESULT: ???",
            stderr: ""
        )
        guard case let .error(reason) = VerifyResultParser.parse(raw) else {
            Issue.record("expected .error outcome")
            return
        }
        #expect(reason.contains("exited with code 2"))
        #expect(reason.contains("stdout (last 5 lines, pipe-joined):"))
        #expect(reason.contains("stderr") == false)
    }

    @Test("very long stderr line is truncated to 200 chars with ellipsis")
    func parseErrorTruncatesLongStderrLine() {
        // 250-char single-line stderr; expect a 200-char prefix + …
        let longLine = String(repeating: "X", count: 250)
        // Exit 2 rather than a signal number: this test is about
        // `parseErrorReason`'s truncation, and a signal routes to the trap
        // diagnosis instead, which quotes only located runtime messages.
        let raw = Self.output(exitCode: 2, stderr: longLine)
        guard case let .error(reason) = VerifyResultParser.parse(raw) else {
            Issue.record("expected .error outcome")
            return
        }
        // The 200-char-prefix-plus-ellipsis form is what `pipeJoinedTail`
        // produces — verify the ellipsis appears (= truncation fired).
        #expect(reason.contains("…"))
        // And the original 250-char "X..." run shouldn't appear verbatim.
        #expect(reason.contains(longLine) == false)
    }
}
