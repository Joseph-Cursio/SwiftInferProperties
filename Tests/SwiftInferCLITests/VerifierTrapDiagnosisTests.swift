import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **A trapped verifier run is not a refutation, and it must not read as one.**
///
/// Measured on the `SeedFocus` idempotence entry over `[Suggestion]`, under
/// lldb, after the closure-binding and build-diagnostics fixes landed:
///
/// ```
/// stop reason = Swift runtime failure: arithmetic overflow
/// frame #1: … implicit closure #3 in Score.init() at Score.swift
/// ```
///
/// `Score.init(signals:)` sums `Signal.weight` with `.reduce(0, +)`. The
/// strategist derives `Gen<Int>.int()` for that field — the full 64-bit range —
/// so two drawn weights overflow and Swift traps. **The law was never
/// evaluated.** `seedIndependent` is neither confirmed nor refuted; the
/// generator simply produced a value the code's arithmetic cannot hold.
///
/// This is the road test's central finding wearing its third costume. A derived
/// generator is tuned for coverage of the **type** and is silently mistuned for
/// the **law** (`§12`, the confident green), for the **collision** (`§13`), and
/// here for the **domain**: `Int` is the type of `weight`, and no part of the
/// type says the sum of eight of them must fit in an `Int`.
///
/// Two things were wrong, and both are about evidence rather than verdicts:
///
///   1. The outcome was already `.error` rather than `.defaultFails`, which is
///      correct — but the reason was `exited with code 5` plus two empty
///      streams, which tells a reader nothing and invites the reading "the tool
///      is broken."
///   2. The stub's `print` is block-buffered when its output is redirected, so
///      the trial number and the input were flushed into oblivion by the trap.
///      Diagnosing this cost two attempts for exactly that reason
///      (`docs/measurements/roadtest-self-dogfood.md` §13.4).
@Suite("A trapped verifier run reports what trapped and why")
struct VerifierTrapDiagnosisTests {

    private static func output(exitCode: Int32, stdout: String = "", stderr: String = "")
        -> VerifierSubprocess.Output {
        VerifierSubprocess.Output(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    // MARK: - Classification

    /// `Process.terminationStatus` reports the bare signal number for an
    /// uncaught signal (5 = SIGTRAP), while a shell reports 128 + 5 = 133.
    /// Both spellings reach this code depending on how the run was launched.
    @Test("both signal spellings are recognised as crashes", arguments: [4, 5, 6, 8, 11, 133, 134])
    func signalExitCodesAreCrashes(code: Int32) {
        let outcome = VerifyResultParser.parse(Self.output(exitCode: code))
        guard case let .error(reason) = outcome else {
            Issue.record("exit \(code) should be .error, got \(outcome)")
            return
        }
        #expect(reason.contains("trapped"), "reason should name the trap: \(reason)")
    }

    /// **The load-bearing assertion.** A crash must never be reported as a
    /// refutation — the law was not evaluated, so calling it false would be a
    /// fabricated counterexample.
    @Test("a crash is never reported as a refutation")
    func crashIsNotARefutation() {
        let outcome = VerifyResultParser.parse(
            Self.output(exitCode: 5, stdout: "VERIFY_DEFAULT_RESULT: FAIL\nVERIFY_DEFAULT_TRIAL: 3")
        )
        if case .defaultFails = outcome {
            Issue.record("a trapped run was reported as a refutation")
        }
    }

    /// An ordinary refutation still exits 1 and must keep working — this is the
    /// control, and without it "never a refutation" could be satisfied by
    /// breaking refutations entirely.
    @Test("an ordinary exit-1 failure is still a refutation")
    func ordinaryFailureStillRefutes() {
        let outcome = VerifyResultParser.parse(
            Self.output(
                exitCode: 1,
                stdout: """
                VERIFY_DEFAULT_RESULT: FAIL
                VERIFY_DEFAULT_TRIAL: 3
                VERIFY_DEFAULT_INPUT: [1, 2]
                VERIFY_DEFAULT_FORWARD: a
                VERIFY_DEFAULT_INVERSE: b
                """
            )
        )
        guard case .defaultFails = outcome else {
            Issue.record("exit 1 with a FAIL marker must refute, got \(outcome)")
            return
        }
    }

    // MARK: - Explainability

    /// The reason must point at the generator's domain, because that is what is
    /// actually wrong and what the reader can act on.
    @Test("the reason explains that the law was not evaluated")
    func reasonExplainsTheLawWasNotEvaluated() {
        guard case let .error(reason) = VerifyResultParser.parse(Self.output(exitCode: 5)) else {
            Issue.record("expected .error")
            return
        }
        #expect(reason.contains("neither confirmed nor refuted"))
        #expect(reason.lowercased().contains("generator"), "must point at the generator domain")
    }

    /// The Swift runtime names the failure on stderr when it survives. When it
    /// does, quote it rather than paraphrasing.
    @Test("a runtime failure message is quoted when present")
    func runtimeFailureIsQuoted() {
        guard case let .error(reason) = VerifyResultParser.parse(
            Self.output(exitCode: 5, stderr: "Swift runtime failure: arithmetic overflow")
        ) else {
            Issue.record("expected .error")
            return
        }
        #expect(reason.contains("arithmetic overflow"))
    }

    /// Whatever the stub managed to flush before trapping is the closest thing
    /// to a counterexample there is, so it must survive into the reason.
    @Test("partial stub output survives into the reason")
    func partialOutputSurvives() {
        guard case let .error(reason) = VerifyResultParser.parse(
            Self.output(exitCode: 5, stdout: "VERIFY_DEFAULT_TRIAL: 7")
        ) else {
            Issue.record("expected .error")
            return
        }
        #expect(reason.contains("VERIFY_DEFAULT_TRIAL: 7"))
    }

    // MARK: - Unbuffered output

    /// **Without this the flush above never happens.** `print` is block-buffered
    /// when stdout is a pipe, which is exactly how the verifier is run, so a
    /// trap discards every marker printed before it.
    @Test("emitted stubs make stdout unbuffered")
    func stubsAreUnbuffered() throws {
        let stub = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "Int",
                typeShape: IndexedTypeShape(
                    name: "Widget",
                    kind: .struct,
                    inheritedTypes: ["Equatable"],
                    hasUserGen: false,
                    storedMembers: [IndexedTypeShape.StoredMember(name: "value", typeName: "Int")]
                ),
                template: "idempotence",
                functionCalls: ["{ (x: Int) in x * x }"],
                seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
                trialBudget: .small
            )
        )
        #expect(stub.contains("setvbuf(stdout"), "a trap must not swallow the markers")
    }
}
