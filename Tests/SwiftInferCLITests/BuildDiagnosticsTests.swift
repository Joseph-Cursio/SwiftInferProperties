import Foundation
@testable import SwiftInferCLI
import Testing

/// **`swift build` writes compile errors to stdout, and the harness only read
/// stderr.**
///
/// Measured on the road-test workdir: exit 1, **235 `error:` lines on stdout,
/// zero bytes on stderr**. Every build failure therefore reported
/// `Last 20 lines of stderr:` followed by nothing, and survey mode reported
/// `build-failed: exit=1` with no detail at all.
///
/// That is why the `SeedFocus` idempotence entry cost three investigations and
/// read as three different problems — a SIGTRAP, then a masked build failure,
/// then a closure-inference error (`docs/roadtest-self-dogfood.md` §13.4). The
/// evidence naming the cause was captured and then thrown away at the last
/// step. A diagnostic that discards the diagnosis is worse than none, because
/// "(no stderr captured)" reads as *the compiler said nothing*.
///
/// The fix is not to guess a stream. Take whichever one carries `error:` lines,
/// and prefer the errors themselves over a positional tail — a 235-line build
/// log's last 20 lines are the summary, not the cause.
@Suite("Build failures surface the compiler's actual diagnosis")
struct BuildDiagnosticsTests {

    private static func output(exitCode: Int32 = 1, stdout: String = "", stderr: String = "")
        -> VerifierSubprocess.Output {
        VerifierSubprocess.Output(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    /// The measured shape: errors on stdout, nothing on stderr.
    private static let swiftPMStdout = """
    [1/3] Compiling SwiftInferVerifier main.swift
    /w/Sources/SwiftInferVerifier/main.swift:135:34: error: cannot find type 'Suggestion' in scope
        |                                  `- error: cannot find type 'Suggestion' in scope
    /w/Sources/SwiftInferVerifier/main.swift:137:20: error: cannot find 'SourceLocation' in scope
    error: fatalError
    [3/3] Build failed
    """

    @Test("compile errors on stdout are surfaced when stderr is empty")
    func stdoutErrorsAreSurfaced() {
        let summary = BuildDiagnostics.summary(from: Self.output(stdout: Self.swiftPMStdout))
        #expect(summary.contains("cannot find type 'Suggestion' in scope"))
        #expect(!summary.isEmpty)
    }

    /// stderr still wins when it has the errors — this is not a swap, it is a
    /// preference for whichever stream actually carries a diagnosis.
    @Test("stderr is preferred when it carries the errors")
    func stderrStillWins() {
        let summary = BuildDiagnostics.summary(
            from: Self.output(stdout: "noise\nnoise", stderr: "/w/x.swift:1:1: error: real cause here")
        )
        #expect(summary.contains("real cause here"))
        #expect(!summary.contains("noise"))
    }

    /// **The line that matters is not the last line.** A 235-line build log ends
    /// in `error: fatalError` and `Build failed`, neither of which names a
    /// cause. A positional tail would have reported exactly those.
    @Test("the summary names a cause, not the log's tail")
    func summaryPrefersCausesOverTail() {
        let summary = BuildDiagnostics.summary(from: Self.output(stdout: Self.swiftPMStdout))
        #expect(summary.contains("cannot find"), "must include a located compiler error")
    }

    /// With no `error:` anywhere, fall back to a tail rather than returning
    /// nothing — a linker or toolchain failure still deserves its output.
    @Test("output with no error: lines still yields something")
    func fallsBackToTail() {
        let summary = BuildDiagnostics.summary(
            from: Self.output(stdout: "ld: framework not found Foo\nclang: linker command failed")
        )
        #expect(summary.contains("framework not found"))
    }

    /// Truly empty output is the one case where "(none captured)" is honest.
    @Test("genuinely empty output says so")
    func emptyOutputIsHonest() {
        #expect(BuildDiagnostics.summary(from: Self.output()).contains("none captured"))
    }

    // MARK: - The two call sites that were dropping it

    @Test("the buildFailed error message includes the compiler's diagnosis")
    func buildFailedMessageIncludesDiagnosis() {
        let message = VerifyError.buildFailed(
            exitCode: 1,
            stderr: BuildDiagnostics.summary(from: Self.output(stdout: Self.swiftPMStdout))
        ).description
        #expect(message.contains("cannot find type 'Suggestion' in scope"))
        #expect(!message.contains("(no stderr captured)"))
    }

    /// Survey mode reported `build-failed: exit=1` and nothing else, across
    /// every entry. The exit code is the least informative part of a build
    /// failure — it is always 1.
    @Test("a survey build-failure detail names the cause, not just the exit code")
    func surveyDetailNamesTheCause() {
        let detail = BuildDiagnostics.surveyDetail(from: Self.output(stdout: Self.swiftPMStdout))
        #expect(detail.hasPrefix("build-failed:"))
        #expect(detail.contains("cannot find type 'Suggestion' in scope"))
    }

    /// Survey records are one JSON line per entry, so the detail must stay
    /// bounded — the point is a legible cause, not the whole build log.
    @Test("the survey detail stays a single bounded line")
    func surveyDetailIsBounded() {
        let huge = (0 ..< 400).map { "/w/f.swift:\($0):1: error: failure number \($0)" }
            .joined(separator: "\n")
        let detail = BuildDiagnostics.surveyDetail(from: Self.output(stdout: huge))
        #expect(!detail.contains("\n"), "a survey record is one line")
        #expect(detail.count < 400, "got \(detail.count) characters")
    }
}
