import Foundation
import Testing

@testable import SwiftInferCLI

// V1.56.B — unit tests for the V1.56.A access-level reclassification
// helper. Validates the stdout/stderr pattern matcher recognizes
// "is inaccessible due to '<access>'" and returns the right detail
// string; non-matching build errors keep the v1.52 .measured-error
// classification (nil return).

@Suite("V1.56.A — architecturalPendingDetail pattern matcher")
struct V156ArchitecturalPendingDetailTests {

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

    // MARK: V1.59.A — instance-member-on-type pattern

    @Test("V1.59.A: matches `instance member ... cannot be used on type`")
    func matchesInstanceMemberError() {
        let stdout = "error: instance member 'sort' cannot be used on type 'OrderedSet<Int>'"
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: stdout,
            buildStderr: ""
        )
        #expect(detail == "instance-method-shape-not-supported")
    }

    @Test("V1.59.A: matches instance-member pattern on stderr stream")
    func matchesInstanceMemberOnStderr() {
        let stderr = """
        main.swift:27:22: error: generic parameter 'Element' could not be inferred
        main.swift:27:22: error: instance member 'sort' cannot be used on type 'OrderedSet<<<hole>>>'
        """
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: "",
            buildStderr: stderr
        )
        #expect(detail == "instance-method-shape-not-supported")
    }

    @Test("internal-access pattern takes precedence over instance-member pattern (consistent ordering)")
    func internalAccessPrecedesInstanceMember() {
        // If both patterns appear (unlikely in real output but the
        // helper's behavior should be deterministic), internal-access
        // wins because it's the more semantically meaningful gap.
        let stdout = """
        error: 'foo' is inaccessible due to 'internal' protection level
        error: instance member 'bar' cannot be used on type 'X'
        """
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: stdout,
            buildStderr: ""
        )
        #expect(detail == "internal-api-not-accessible")
    }

    // MARK: V1.59.A — additional patterns

    @Test("V1.59.A: matches `no exact matches in call to instance method`")
    func matchesNoExactMatchesInstance() {
        let stdout = "error: no exact matches in call to instance method 'subtract'"
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: stdout,
            buildStderr: ""
        )
        #expect(detail == "instance-method-shape-not-supported")
    }

    @Test("V1.59.A: matches `compile command failed due to signal` (compiler crash)")
    func matchesCompilerCrash() {
        let stdout = """
        error: emit-module command failed due to signal 6 (use -v to see invocation)
        error: compile command failed due to signal 6 (use -v to see invocation)
        """
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: stdout,
            buildStderr: ""
        )
        #expect(detail == "instance-method-shape-not-supported")
    }

    @Test("V1.63.A: matches `generic parameter ... could not be inferred`")
    func matchesGenericParameterInference() {
        let stdout = "error: generic parameter 'Key' could not be inferred"
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: stdout,
            buildStderr: ""
        )
        #expect(detail == "instance-method-shape-not-supported")
    }

    @Test("V1.59.A: matches `requires that X conform to Y` (carrier-conformance gap)")
    func matchesConformanceRequirement() {
        let stdout = """
        error: global function 'min' requires that 'OrderedSet<Int>' conform to 'Comparable'
        """
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: stdout,
            buildStderr: ""
        )
        #expect(detail == "carrier-missing-required-conformance")
    }

    // MARK: - Protocol-carrier (existential) instance-method variant

    @Test("matches `type 'any P' has no member 'x'` (static-called instance method on a protocol)")
    func matchesExistentialCarrierNoMember() {
        // The real diagnostic from static-calling `StringProtocol`'s
        // `addingIntercappedPrefix(_:)` — an instance method emitted as
        // `StringProtocol.addingIntercappedPrefix(x)`. Reclassifies the
        // otherwise-opaque `build-failed` into the instance-method-shape gap.
        let stdout =
            "main.swift:26:37: error: type 'any StringProtocol' has no member 'addingIntercappedPrefix'"
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: stdout,
            buildStderr: ""
        )
        #expect(detail == "instance-method-shape-not-supported")
    }

    @Test("requires both `type 'any` and `has no member` — a plain missing member alone does not match")
    func plainMissingMemberDoesNotMatch() {
        // A missing member on a concrete type (no `any` existential) is an
        // ordinary emitter/typo error and must stay `.measured-error` (nil).
        let detail = SwiftInferCommand.Verify.architecturalPendingDetail(
            buildStdout: "error: value of type 'Int' has no member 'wobble'",
            buildStderr: ""
        )
        #expect(detail == nil)
    }
}
