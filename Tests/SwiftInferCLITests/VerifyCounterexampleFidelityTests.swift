import Foundation
import Testing

@testable import SwiftInferCLI

// V1.151 — a whitespace-significant counterexample (e.g. `"  -"` from an
// indentation/idempotence function) must survive parsing faithfully and
// render unambiguously, instead of collapsing to a bare `-`.
@Suite("Verify counterexample fidelity — V1.151")
struct VerifyCounterexampleFidelityTests {

    private func output(_ stdout: String, exit: Int32 = 1) -> VerifierSubprocess.Output {
        VerifierSubprocess.Output(exitCode: exit, stdout: stdout, stderr: "")
    }

    @Test("parse preserves a counterexample's own leading/trailing whitespace")
    func parsePreservesWhitespace() {
        let stdout = """
        VERIFY_DEFAULT_RESULT: FAIL
        VERIFY_DEFAULT_TRIAL: 3
        VERIFY_DEFAULT_INPUT: -
        VERIFY_DEFAULT_FORWARD:   -
        VERIFY_DEFAULT_INVERSE:     -
        """
        guard case let .defaultFails(detail) = VerifyResultParser.parse(output(stdout)) else {
            Issue.record("expected .defaultFails")
            return
        }
        #expect(detail.input == "-")
        // The single separator space after the colon is stripped, but the
        // value's own leading spaces are preserved (not collapsed to "-").
        #expect(detail.forwardResult == "  -")
        #expect(detail.inverseResult == "    -")
    }

    @Test("numeric markers are unaffected (only the separator space is stripped)")
    func numericMarkersUnaffected() {
        let stdout = """
        VERIFY_DEFAULT_RESULT: FAIL
        VERIFY_DEFAULT_TRIAL: 7
        VERIFY_DEFAULT_INPUT: 42
        VERIFY_DEFAULT_FORWARD: 43
        VERIFY_DEFAULT_INVERSE: 44
        """
        guard case let .defaultFails(detail) = VerifyResultParser.parse(output(stdout)) else {
            Issue.record("expected .defaultFails")
            return
        }
        #expect(detail.trial == 7)
        #expect(detail.input == "42")
    }

    @Test("displayValue quotes whitespace/empty values, leaves ordinary ones raw")
    func displayValueQuoting() {
        #expect(VerifyResultRenderer.displayValue("  -") == "\"  -\"")
        #expect(VerifyResultRenderer.displayValue("- ") == "\"- \"")
        #expect(VerifyResultRenderer.displayValue("a\nb") == "\"a\\nb\"")
        #expect(VerifyResultRenderer.displayValue("") == "\"\"")
        // Ordinary values render unchanged — numeric output is untouched.
        #expect(VerifyResultRenderer.displayValue("42") == "42")
        #expect(VerifyResultRenderer.displayValue("hello") == "hello")
        #expect(VerifyResultRenderer.displayValue("(1.0, 2.0)") == "(1.0, 2.0)")
    }
}
