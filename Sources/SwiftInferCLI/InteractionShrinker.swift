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

    /// V2.0 M8.D.3 / M8.D.4 — closure-shaped runner so unit tests
    /// can inject synthetic exit-code-bearing logic instead of
    /// spawning real binaries. The closure receives the sequence
    /// index + window (`suffixStart`, `prefixLength`) and returns a
    /// process exit code (non-zero = trap). M8.D.3 only varied
    /// `prefixLength`; M8.D.4 adds the `suffixStart` axis.
    public struct Runner: Sendable {
        public let invoke: @Sendable (
            _ sequenceIndex: Int,
            _ suffixStart: Int,
            _ prefixLength: Int
        ) -> Int32

        public init(
            invoke: @escaping @Sendable (
                _ sequenceIndex: Int,
                _ suffixStart: Int,
                _ prefixLength: Int
            ) -> Int32
        ) {
            self.invoke = invoke
        }
    }

    /// V2.0 M8.D.4 — the result of running both shrink phases on a
    /// failing trace. The persisted trace replays
    /// `rawActions.dropFirst(suffixStart).prefix(prefixLength)`.
    public struct ShrinkResult: Equatable, Sendable {
        public let suffixStart: Int
        public let prefixLength: Int

        public init(suffixStart: Int, prefixLength: Int) {
            self.suffixStart = suffixStart
            self.prefixLength = prefixLength
        }
    }

    /// V2.0 M8.D.3 — binary-search the smallest prefix length whose
    /// pinned-sequence replay (at suffix-start = 0) still traps.
    /// Returns a non-negative integer in `[0, upperBound]`. Phase 1
    /// of the two-phase shrink shipped at M8.D.4.
    public static func shrinkPrefix(
        failingSequenceIndex: Int,
        upperBound: Int,
        runner: Runner
    ) -> Int {
        var low = -1
        var high = upperBound
        while low + 1 < high {
            let mid = (low + high) / 2
            let exitCode = runner.invoke(failingSequenceIndex, 0, mid)
            if exitCode != 0 {
                high = mid
            } else {
                low = mid
            }
        }
        return high
    }

    /// V2.0 M8.D.4 — binary-search the largest suffix-start that
    /// still traps when the prefix length is pinned to `prefixLength`.
    /// Returns a non-negative integer in `[0, upperBound -
    /// prefixLength]`. Phase 2 of the two-phase shrink.
    ///
    /// **Why "largest start that still traps."** Drop-prefix slides
    /// the window forward as long as the trap is preserved. The
    /// answer is the maximum start such that
    /// `rawActions[start..<start+prefixLength]` still trips the
    /// reducer.
    public static func shrinkSuffixStart(
        failingSequenceIndex: Int,
        prefixLength: Int,
        upperBound: Int,
        runner: Runner
    ) -> Int {
        // Invariant: `low` is the largest known-trapping start; `high`
        // is the smallest known-passing start. Range `[0, upperBound -
        // prefixLength]`. Initially `low = 0` (we assume the prior
        // phase's start=0 still traps) and `high = max + 1` (a
        // sentinel one past the search space).
        let maxStart = max(0, upperBound - prefixLength)
        var low = 0
        var high = maxStart + 1
        while low + 1 < high {
            let mid = (low + high) / 2
            let exitCode = runner.invoke(failingSequenceIndex, mid, prefixLength)
            if exitCode != 0 {
                low = mid
            } else {
                high = mid
            }
        }
        return low
    }

    /// V2.0 M8.D.4 — top-level two-phase shrink. Runs `shrinkPrefix`
    /// first to find the minimum trap-inducing length, then
    /// `shrinkSuffixStart` with that length pinned to find the
    /// largest start offset that still traps. Returns the combined
    /// `(suffixStart, prefixLength)` window. Total cost is
    /// O(log²(upperBound)) re-invocations — bounded by ~25 for the
    /// default upperBound=16, sub-second wall time.
    public static func shrink(
        failingSequenceIndex: Int,
        upperBound: Int,
        runner: Runner
    ) -> ShrinkResult {
        let prefixLength = shrinkPrefix(
            failingSequenceIndex: failingSequenceIndex,
            upperBound: upperBound,
            runner: runner
        )
        let suffixStart = shrinkSuffixStart(
            failingSequenceIndex: failingSequenceIndex,
            prefixLength: prefixLength,
            upperBound: upperBound,
            runner: runner
        )
        return ShrinkResult(suffixStart: suffixStart, prefixLength: prefixLength)
    }

    /// V2.0 M8.D.3 / M8.D.4 — concrete `Runner` that invokes the
    /// verifier binary in `workdir` with the M8.D.2 + M8.D.4 pin
    /// env vars. Tests prefer the closure-based `Runner.init` for
    /// hermetic suites.
    public static func liveRunner(workdir: URL) -> Runner {
        Runner { sequenceIndex, suffixStart, prefixLength in
            let env = [
                ActionSequenceStubEmitter.pinSequenceEnvVar: "\(sequenceIndex)",
                ActionSequenceStubEmitter.pinSuffixStartEnvVar: "\(suffixStart)",
                ActionSequenceStubEmitter.pinPrefixLengthEnvVar: "\(prefixLength)"
            ]
            do {
                let output = try VerifierSubprocess.runVerifierBinary(
                    workdir: workdir,
                    extraEnvironment: env
                )
                return output.exitCode
            } catch {
                // Subprocess-launch failure → conservative non-zero.
                return 1
            }
        }
    }
}
