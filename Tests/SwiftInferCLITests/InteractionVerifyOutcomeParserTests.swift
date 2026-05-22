import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V2.0 M3.E.3 — outcome-parser tests. Pure: no subprocess, no I/O.
// Each test feeds hand-crafted stdout + an exit code and asserts
// on the mapped VerifyEvidenceOutcome.

@Suite("InteractionVerifyOutcomeParser — V2.0 M3.E.3 five-category mapping")
struct InteractionVerifyOutcomeParserTests {

    private func cleanMarker(totalRuns: Int = 1_024, clean: Int = 1_024) -> String {
        "\(ActionSequenceStubEmitter.cleanOutcomeMarker) "
            + "totalRuns=\(totalRuns) clean=\(clean)\n"
    }

    // MARK: - parseRunOutput

    @Test("exit code 0 + marker → .measuredBothPass with totalRuns + cleanRuns")
    func cleanExitWithMarker() {
        let result = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: 0,
            stdout: cleanMarker(totalRuns: 1_024, clean: 1_024)
        )
        #expect(result.outcome == .measuredBothPass)
        #expect(result.totalRuns == 1_024)
        #expect(result.cleanRuns == 1_024)
    }

    @Test("marker on a stdout line surrounded by noise still parses")
    func markerAmongNoise() {
        let stdout = "some other output\n"
            + cleanMarker(totalRuns: 100, clean: 100)
            + "trailing noise\n"
        let result = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: 0,
            stdout: stdout
        )
        #expect(result.outcome == .measuredBothPass)
        #expect(result.totalRuns == 100)
    }

    @Test("non-zero exit code → .measuredDefaultFails — reducer trapped")
    func nonZeroExitIsDefaultFails() {
        let result = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: 134, // SIGABRT — typical Swift trap exit
            stdout: ""
        )
        #expect(result.outcome == .measuredDefaultFails)
        #expect(result.detail?.contains("134") == true)
    }

    @Test("exit code 0 with no marker → .measuredError — stub bug or version skew")
    func missingMarkerIsMeasuredError() {
        let result = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: 0,
            stdout: "ran a bit but said nothing recognizable"
        )
        #expect(result.outcome == .measuredError)
    }

    @Test("marker with missing fields → .measuredError")
    func markerMissingFieldsIsMeasuredError() {
        let result = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: 0,
            stdout: ActionSequenceStubEmitter.cleanOutcomeMarker + " totalRuns=42\n"
        )
        // Missing `clean=` — extractMarker returns nil, falls through to .measuredError.
        #expect(result.outcome == .measuredError)
    }

    // MARK: - parseBuildFailure

    @Test("build failure → .architecturalCoveragePending with stderr snippet")
    func buildFailureIsArchitecturalCoveragePending() {
        let result = InteractionVerifyOutcomeParser.parseBuildFailure(
            buildExitCode: 1,
            stderr: "error: cannot find 'AppState' in scope\nerror: cannot find 'reduce' in scope"
        )
        #expect(result.outcome == .architecturalCoveragePending)
        #expect(result.detail?.contains("exit code 1") == true)
        #expect(result.detail?.contains("cannot find 'AppState'") == true)
    }

    // MARK: - extractMarker (low-level)

    @Test("extractMarker pulls totalRuns + clean from a well-formed line")
    func extractMarkerExtractsFields() {
        let fields = InteractionVerifyOutcomeParser.extractMarker(
            from: cleanMarker(totalRuns: 256, clean: 200)
        )
        #expect(fields?.totalRuns == 256)
        #expect(fields?.cleanRuns == 200)
    }

    @Test("extractMarker on empty input returns nil")
    func extractMarkerEmpty() {
        let fields = InteractionVerifyOutcomeParser.extractMarker(from: "")
        #expect(fields == nil)
    }

    // MARK: - V2.0 M8.D.1 — failing-sequence-index recovery

    @Test("non-zero exit + TRACE-CURRENT-SEQ in stderr → failingSequenceIndex recovered")
    func nonZeroExitWithTraceMarker() {
        let stderr = """
        TRACE-CURRENT-SEQ: 0
        TRACE-CURRENT-SEQ: 1
        TRACE-CURRENT-SEQ: 42
        """
        let result = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: 134,
            stdout: "",
            stderr: stderr
        )
        #expect(result.outcome == .measuredDefaultFails)
        #expect(result.failingSequenceIndex == 42)
        #expect(result.detail?.contains("at sequence index 42") == true)
    }

    @Test("non-zero exit with no TRACE-CURRENT-SEQ markers → failingSequenceIndex nil")
    func nonZeroExitWithoutTraceMarker() {
        let result = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: 134,
            stdout: "",
            stderr: ""
        )
        #expect(result.outcome == .measuredDefaultFails)
        #expect(result.failingSequenceIndex == nil)
    }

    @Test("extractFailingSequenceIndex returns the LAST marker, not the first")
    func extractFailingIndexReturnsLast() {
        let stderr = "TRACE-CURRENT-SEQ: 5\nTRACE-CURRENT-SEQ: 7\nTRACE-CURRENT-SEQ: 12\n"
        let index = InteractionVerifyOutcomeParser.extractFailingSequenceIndex(from: stderr)
        #expect(index == 12)
    }

    @Test("extractFailingSequenceIndex on empty input returns nil")
    func extractFailingIndexEmpty() {
        let index = InteractionVerifyOutcomeParser.extractFailingSequenceIndex(from: "")
        #expect(index == nil)
    }

    @Test("extractFailingSequenceIndex ignores lines without the marker prefix")
    func extractFailingIndexIgnoresNoise() {
        let stderr = """
        some build chatter
        TRACE-CURRENT-SEQ: 3
        random log line
        TRACE-CURRENT-SEQ: 99
        end-of-output
        """
        let index = InteractionVerifyOutcomeParser.extractFailingSequenceIndex(from: stderr)
        #expect(index == 99)
    }
}
