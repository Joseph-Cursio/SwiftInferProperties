import Foundation
import SwiftInferCore

/// V2.0 M8.D.3 — binary-search shrinker over the M8.D.2 pin-sequence
/// + prefix-length env-var primitive. Given a failing sequence index
/// (recovered by M8.D.1's stderr marker), this finds the **minimum
/// action-prefix length** that still causes the verifier to trap.
///
/// **Strategy.** Drop-suffix / halving — repeatedly halve the prefix
/// length and check whether the trap survives. Each shrink step
/// re-runs the verifier binary with `SWIFT_INFER_PIN_SEQUENCE=<i>`
/// and `SWIFT_INFER_PIN_PREFIX_LENGTH=<k>`. The Xoshiro256** seed is
/// fixed (matches the original run), so each re-invocation produces
/// the same `rawActions` list; only the prefix length varies.
///
/// **What this doesn't do.** Drop-prefix shrinking (chopping from the
/// head) is deferred — the stub only exposes prefix-length truncation
/// at M8.D.2, not arbitrary slicing. PRD §7.2 #3 mentions "drop-prefix
/// / drop-suffix / halving" as a class; shipping drop-suffix-by-
/// halving is a meaningful subset that covers most failing
/// trajectories where the trap-relevant actions cluster early in the
/// sequence.
///
/// **Correctness.** Binary search invariant: `low` is the largest
/// known-passing prefix length (initially -1, "no known-passing
/// length"), `high` is the smallest known-trapping prefix length
/// (initially `upperBound`, the original sequence's length). Each
/// step tests `mid = (low + high) / 2`; on trap, `high = mid`; on
/// pass, `low = mid`. Terminates when `low + 1 == high`; the answer
/// is `high`.
public enum InteractionShrinker {

    /// V2.0 M8.D.3 — closure-shaped runner so unit tests can inject
    /// synthetic exit-code-bearing logic instead of spawning real
    /// binaries. The closure receives the sequence index + prefix
    /// length and returns a process exit code (non-zero = trap).
    public struct Runner: Sendable {
        public let invoke: @Sendable (_ sequenceIndex: Int, _ prefixLength: Int) -> Int32

        public init(
            invoke: @escaping @Sendable (_ sequenceIndex: Int, _ prefixLength: Int) -> Int32
        ) {
            self.invoke = invoke
        }
    }

    /// V2.0 M8.D.3 — binary-search the smallest prefix length whose
    /// pinned-sequence replay still traps. Returns a non-negative
    /// integer in `[0, upperBound]`. The caller threads the result
    /// into `InteractionTraceEmitter.Inputs.minimumFailingPrefixLength`
    /// so the persisted trace file replays only the minimal
    /// trap-inducing action prefix.
    ///
    /// **Inputs.**
    /// - `failingSequenceIndex`: from M8.D.1's parser.
    /// - `upperBound`: the verifier's `lengthUpperBound` (max possible
    ///   action-list length). We assume this length traps; that's the
    ///   precondition for invoking the shrinker.
    /// - `runner`: how to invoke the verifier with pin env vars.
    public static func shrinkPrefix(
        failingSequenceIndex: Int,
        upperBound: Int,
        runner: Runner
    ) -> Int {
        var low = -1
        var high = upperBound
        // Each loop step shrinks the [low, high] interval; the
        // search runs in O(log N) re-invocations.
        while low + 1 < high {
            let mid = (low + high) / 2
            let exitCode = runner.invoke(failingSequenceIndex, mid)
            if exitCode != 0 {
                high = mid
            } else {
                low = mid
            }
        }
        return high
    }

    /// V2.0 M8.D.3 — concrete `Runner` that invokes the verifier
    /// binary in `workdir` with the M8.D.2 pin env vars. Used by the
    /// pipeline; tests prefer the closure-based `Runner.init` to keep
    /// the suite hermetic.
    public static func liveRunner(workdir: URL) -> Runner {
        Runner { sequenceIndex, prefixLength in
            let env = [
                ActionSequenceStubEmitter.pinSequenceEnvVar: "\(sequenceIndex)",
                ActionSequenceStubEmitter.pinPrefixLengthEnvVar: "\(prefixLength)"
            ]
            do {
                let output = try VerifierSubprocess.runVerifierBinary(
                    workdir: workdir,
                    extraEnvironment: env
                )
                return output.exitCode
            } catch {
                // Treat subprocess-launch failures as a non-zero exit
                // — conservative; the shrinker can't make progress
                // and the trap-inducing length defaults to whatever
                // bound the binary search had landed on.
                return 1
            }
        }
    }
}
