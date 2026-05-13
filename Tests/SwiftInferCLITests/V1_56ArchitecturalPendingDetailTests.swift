import Foundation
import Testing

@testable import SwiftInferCLI

// V1.56.B — unit tests for the V1.56.A access-level reclassification
// helper. Validates the stdout/stderr pattern matcher recognizes
// "is inaccessible due to '<access>'" and returns the right detail
// string; non-matching build errors keep the v1.52 .measured-error
// classification (nil return).

@Suite("V1.56.A — architecturalPendingDetail pattern matcher")
struct V1_56ArchitecturalPendingDetailTests {

    @Test("matches `is inaccessible due to 'internal'` on stdout")
    func matchesInternalOnStdout() {
        let stdout = """
        Building for debugging...
        error: 'rescaledDivide' is inaccessible due to 'internal' protection level
        """
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: stdout,
            buildStderr: ""
        )
        #expect(detail == "internal-api-not-accessible")
    }

    @Test("matches `is inaccessible due to 'private'` on stderr (fallback stream)")
    func matchesPrivateOnStderr() {
        let stderr = "main.swift:42:10: error: 'helper' is inaccessible due to 'private' protection level"
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: "",
            buildStderr: stderr
        )
        #expect(detail == "internal-api-not-accessible")
    }

    @Test("matches `fileprivate` (any of the three access modifiers)")
    func matchesFileprivate() {
        let stdout = "error: 'foo' is inaccessible due to 'fileprivate' protection level"
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: stdout,
            buildStderr: ""
        )
        #expect(detail == "internal-api-not-accessible")
    }

    @Test("returns nil for unrelated build errors (preserves measured-error classification)")
    func returnsNilForUnrelatedErrors() {
        let stdout = """
        error: cannot find 'unknownSymbol' in scope
        error: missing argument for parameter 'foo'
        """
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: stdout,
            buildStderr: ""
        )
        #expect(detail == nil)
    }

    @Test("returns nil for empty stdout + stderr")
    func returnsNilForEmpty() {
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: "",
            buildStderr: ""
        )
        #expect(detail == nil)
    }

    @Test("returns the detail when the pattern appears on either stream")
    func matchesEitherStream() {
        let onlyStdout = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: "is inaccessible due to 'internal'",
            buildStderr: ""
        )
        let onlyStderr = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: "",
            buildStderr: "is inaccessible due to 'internal'"
        )
        #expect(onlyStdout == "internal-api-not-accessible")
        #expect(onlyStderr == "internal-api-not-accessible")
    }
}
