import Foundation
@testable import SwiftInferCLI
import Testing

/// Self-dogfood road test (`docs/roadtest-self-dogfood.md` §11.2) — the bound
/// that turns a hung verifier into a verdict.
///
/// A generated property can fail to terminate. The strategist's
/// `.rawRepresentable` recipe for a `String`-raw enum emits
/// `Gen<Character>.letterOrNumber.string(of: 0...8).compactMap { T(rawValue: $0) }`
/// — random strings filtered for ones that happen to be a valid raw value —
/// which for any real enum essentially never produces a value. During the road
/// test two such binaries spun at 100% CPU for over an hour while the survey
/// reported nothing at all.
///
/// That failure mode is worse than the compile errors beside it. A stub that
/// fails to build is loud. A stub that compiles, runs, and hangs yields no
/// verdict, no error and no output — the survey just stops, and the operator
/// concludes it is slow. `runVerifierBinary` now bounds the wait.
///
/// These tests drive `runProcess` through real subprocesses rather than a fake,
/// because every interesting part of this is real-process behaviour: whether a
/// child that ignores SIGTERM is escalated to SIGKILL, and whether a child that
/// outfills the pipe buffer deadlocks the reader.
@Suite("Verifier subprocess — a hung run becomes a verdict, not a wedge")
struct VerifierTimeoutTests {

    private static let scratch = FileManager.default.temporaryDirectory

    /// A run that exceeds its deadline is killed and reported — not waited on.
    /// Bounded at ~1s so the test is fast; the production ceiling is 300s.
    @Test("a run past its deadline is killed and surfaces as timed-out")
    func hungRunTimesOut() throws {
        let started = Date()
        var thrown: (any Error)?
        do {
            _ = try VerifierSubprocess.runProcessForTesting(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["60"],
                workingDirectory: Self.scratch,
                timeout: 1
            )
        } catch {
            thrown = error
        }
        let elapsed = Date().timeIntervalSince(started)

        #expect(thrown != nil, "a hung run must throw rather than return")
        #expect(elapsed < 20, "the wait was not bounded — took \(elapsed)s")
        guard case let .runnerCrashed(reason)? = thrown as? VerifyError else {
            Issue.record("expected .runnerCrashed, got \(String(describing: thrown))")
            return
        }
        // The prefix is load-bearing: the survey keys on it to classify the
        // outcome as `measured-error` rather than architectural-coverage-pending.
        #expect(reason.hasPrefix("timed-out:"), "reason must be survey-classifiable: \(reason)")
    }

    /// **A child that ignores SIGTERM is still killed.** A generator stuck in a
    /// tight `compactMap` retry loop is exactly that child, so terminate-only
    /// would leave the process alive and the CPU pegged even after the survey
    /// moved on — which is how two of them accumulated an hour of runtime.
    @Test("a SIGTERM-ignoring child is escalated to SIGKILL")
    func sigtermIgnoringChildIsKilled() throws {
        let script = Self.scratch.appendingPathComponent("ignore-sigterm-\(UUID().uuidString).sh")
        try """
        #!/bin/sh
        trap '' TERM
        while :; do :; done
        """.write(to: script, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: script) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let started = Date()
        #expect(throws: VerifyError.self) {
            _ = try VerifierSubprocess.runProcessForTesting(
                executable: script,
                arguments: [],
                workingDirectory: Self.scratch,
                timeout: 1
            )
        }
        // 1s deadline + 2s SIGTERM grace + kill. Anything near 60 means the
        // escalation never happened.
        #expect(Date().timeIntervalSince(started) < 20)
    }

    /// A child that outfills the 64 KB pipe buffer must not deadlock the reader.
    ///
    /// The previous implementation read both pipes *after* `waitUntilExit`, so a
    /// chatty verifier blocked writing while the harness blocked waiting — a
    /// hang indistinguishable from the one above, and one a timeout would
    /// mis-report as a non-terminating property. Draining concurrently fixes it;
    /// this pins that it stays fixed.
    @Test("a child that outfills the pipe buffer times out instead of deadlocking")
    func largeOutputDoesNotDeadlock() {
        let started = Date()
        var reason = ""
        do {
            _ = try VerifierSubprocess.runProcessForTesting(
                // `yes` never exits and floods stdout — far past the 64 KB buffer.
                executable: URL(fileURLWithPath: "/usr/bin/yes"),
                arguments: [String(repeating: "x", count: 60)],
                workingDirectory: Self.scratch,
                timeout: 2
            )
            Issue.record("expected the deadline to fire")
        } catch let error as VerifyError {
            if case let .runnerCrashed(text) = error { reason = text }
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        // Bounded — the old read-after-wait ordering would block here forever.
        #expect(Date().timeIntervalSince(started) < 20)
        #expect(reason.hasPrefix("timed-out:"))
        // **The load-bearing assertion.** Partial stdout survived, which proves
        // the pipe was being drained concurrently rather than after the wait.
        // Had it deadlocked, there would be no output to report and the
        // diagnostic would be empty.
        #expect(
            reason.contains("Partial stdout: xxx"),
            "the drained output was lost — the reader is not concurrent"
        )
    }

    /// The ordinary path is unchanged: a fast, well-behaved child returns its
    /// exit code and output. A timeout that broke normal runs would be worse
    /// than the hang.
    @Test("a normal run is unaffected by the deadline")
    func normalRunIsUnaffected() throws {
        let output = try VerifierSubprocess.runProcessForTesting(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["VERIFY_DEFAULT_RESULT: PASS"],
            workingDirectory: Self.scratch,
            timeout: 30
        )
        #expect(output.exitCode == 0)
        #expect(output.stdout.contains("VERIFY_DEFAULT_RESULT: PASS"))
    }

    /// A non-zero exit is reported, not thrown — the verifier exits 1 on a
    /// genuine `defaultFails`, and that is a verdict rather than an error.
    @Test("a non-zero exit is a result, not a timeout")
    func nonZeroExitIsAResult() throws {
        let output = try VerifierSubprocess.runProcessForTesting(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo VERIFY_DEFAULT_RESULT: FAIL; exit 1"],
            workingDirectory: Self.scratch,
            timeout: 30
        )
        #expect(output.exitCode == 1)
        #expect(output.stdout.contains("FAIL"))
    }

    /// `nil` disables the bound, preserving the pre-existing behaviour for
    /// callers that deliberately want to wait.
    @Test("a nil timeout waits normally")
    func nilTimeoutWaitsNormally() throws {
        let output = try VerifierSubprocess.runProcessForTesting(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["ok"],
            workingDirectory: Self.scratch,
            timeout: nil
        )
        #expect(output.exitCode == 0)
    }
}
