import Foundation
import Testing
@testable import SwiftInferCLI

// V2.0 M8.D.3 — binary-search shrinker correctness. Pure: every
// test injects a synthetic `Runner` whose closure returns a fixed
// exit-code-bearing rule, exercising the shrinker without spawning
// a real binary.

@Suite("InteractionShrinker — V2.0 M8.D.3 binary-search shrinker")
struct InteractionShrinkerTests {

    /// One call to the shrinker's `Runner.invoke`. SwiftLint caps
    /// tuple arity at 2; using a struct keeps the recorder readable
    /// as the M8.D.4 axis count grew.
    struct Invocation: Equatable {
        let sequenceIndex: Int
        let suffixStart: Int
        let prefixLength: Int
    }

    /// Runner that traps iff `prefixLength >= threshold` regardless
    /// of `suffixStart`. Models the canonical M8.D.3 case: "the trap
    /// needs at least N actions in the sequence, anywhere in the
    /// window."
    private final class ThresholdRunner: @unchecked Sendable {
        let threshold: Int
        var invocations: [Invocation] = []

        init(threshold: Int) {
            self.threshold = threshold
        }

        func runner() -> InteractionShrinker.Runner {
            InteractionShrinker.Runner { [self] sequenceIndex, suffixStart, prefixLength in
                invocations.append(Invocation(
                    sequenceIndex: sequenceIndex,
                    suffixStart: suffixStart,
                    prefixLength: prefixLength
                ))
                return prefixLength >= threshold ? 1 : 0
            }
        }
    }

    // MARK: - Threshold-shape correctness

    @Test("shrinkPrefix finds the exact threshold when threshold > 0 and < upperBound")
    func findsThresholdInMiddle() {
        let recorder = ThresholdRunner(threshold: 5)
        let result = InteractionShrinker.shrinkPrefix(
            failingSequenceIndex: 42,
            upperBound: 16,
            runner: recorder.runner()
        )
        #expect(result == 5)
    }

    @Test("shrinkPrefix returns upperBound when only the full length traps")
    func returnsUpperBoundWhenOnlyFullLengthTraps() {
        let recorder = ThresholdRunner(threshold: 16)
        let result = InteractionShrinker.shrinkPrefix(
            failingSequenceIndex: 0,
            upperBound: 16,
            runner: recorder.runner()
        )
        #expect(result == 16)
    }

    @Test("shrinkPrefix returns 0 when even an empty action list traps")
    func returnsZeroWhenEmptyTraps() {
        let recorder = ThresholdRunner(threshold: 0)
        let result = InteractionShrinker.shrinkPrefix(
            failingSequenceIndex: 7,
            upperBound: 16,
            runner: recorder.runner()
        )
        #expect(result == 0)
    }

    @Test("shrinkPrefix returns 1 when a single action is sufficient")
    func returnsOneWhenSingleActionTraps() {
        let recorder = ThresholdRunner(threshold: 1)
        let result = InteractionShrinker.shrinkPrefix(
            failingSequenceIndex: 0,
            upperBound: 16,
            runner: recorder.runner()
        )
        #expect(result == 1)
    }

    // MARK: - Search-path properties

    @Test("shrinkPrefix runs in O(log upperBound) invocations")
    func searchIsLogarithmic() {
        let recorder = ThresholdRunner(threshold: 5)
        _ = InteractionShrinker.shrinkPrefix(
            failingSequenceIndex: 0,
            upperBound: 16,
            runner: recorder.runner()
        )
        // log2(16) = 4; the binary search makes at most ⌈log2(N+1)⌉
        // invocations. 5 is the tight upper bound for N=16; allow a
        // small slack.
        #expect(recorder.invocations.count <= 6)
    }

    @Test("shrinkPrefix forwards the failing sequence index to every invocation")
    func forwardsSequenceIndex() {
        let recorder = ThresholdRunner(threshold: 5)
        _ = InteractionShrinker.shrinkPrefix(
            failingSequenceIndex: 99,
            upperBound: 16,
            runner: recorder.runner()
        )
        for invocation in recorder.invocations {
            #expect(invocation.sequenceIndex == 99)
        }
    }

    @Test("shrinkPrefix never invokes outside [0, upperBound]")
    func searchStaysInBounds() {
        let recorder = ThresholdRunner(threshold: 3)
        _ = InteractionShrinker.shrinkPrefix(
            failingSequenceIndex: 0,
            upperBound: 16,
            runner: recorder.runner()
        )
        for invocation in recorder.invocations {
            #expect(invocation.prefixLength >= 0)
            #expect(invocation.prefixLength <= 16)
        }
    }

    // MARK: - liveRunner construction

    @Test("liveRunner builds a Runner closure tied to a workdir (smoke)")
    func liveRunnerSmoke() {
        let workdir = URL(fileURLWithPath: "/tmp/never-exists-\(UUID())")
        let runner = InteractionShrinker.liveRunner(workdir: workdir)
        // The closure exists and is callable; we don't invoke it
        // because the binary doesn't exist (would throw and fall
        // through to the conservative exit-code-1 return).
        _ = runner.invoke
    }
}

// V2.0 M8.D.4 — drop-prefix (`shrinkSuffixStart`) + top-level
// `shrink` correctness. Extension-grouped so the parent suite stays
// under SwiftLint's type_body_length cap.
extension InteractionShrinkerTests {

    /// Runner that traps iff the action window `[suffixStart,
    /// suffixStart+prefixLength)` overlaps with a fixed "trap index"
    /// in the original action list. Models the canonical M8.D.4
    /// case: "action at index K is the trap-inducing one."
    private final class TrapIndexRunner: @unchecked Sendable {
        let trapIndex: Int

        init(trapIndex: Int) {
            self.trapIndex = trapIndex
        }

        func runner() -> InteractionShrinker.Runner {
            InteractionShrinker.Runner { [self] _, suffixStart, prefixLength in
                let endExclusive = suffixStart + prefixLength
                let containsTrap = suffixStart <= trapIndex && trapIndex < endExclusive
                return containsTrap ? 1 : 0
            }
        }
    }

    // MARK: - shrinkSuffixStart correctness
    //
    // **Algorithm invariant.** `shrinkSuffixStart` assumes the trap-
    // coverage function over `start` is monotonically `true`-then-
    // `false` — i.e., there exists some threshold T such that all
    // start values ≤ T trap and all start values > T pass. Phase 1
    // (`shrinkPrefix`) ensures this by returning the smallest L such
    // that `[0, L)` covers the trap, which makes L > trapIndex. With
    // L > trapIndex, the coverage function over start is exactly
    // `start ≤ trapIndex`, which is monotonic. Tests below respect
    // this invariant.

    @Test("shrinkSuffixStart finds the trap-index when prefixLength > trapIndex (tail trap)")
    func suffixStartAtTail() {
        // Trap at index 7. Phase 1 (in real use) returns L=8; we
        // pass L=8 to phase 2. Largest start whose [start..start+8)
        // window still covers index 7 = 7.
        let recorder = TrapIndexRunner(trapIndex: 7)
        let result = InteractionShrinker.shrinkSuffixStart(
            failingSequenceIndex: 0,
            prefixLength: 8,
            upperBound: 16,
            runner: recorder.runner()
        )
        #expect(result == 7)
    }

    @Test("shrinkSuffixStart returns 0 when trap is at index 0 (no drop possible)")
    func suffixStartAtHead() {
        let recorder = TrapIndexRunner(trapIndex: 0)
        let result = InteractionShrinker.shrinkSuffixStart(
            failingSequenceIndex: 0,
            prefixLength: 1,
            upperBound: 16,
            runner: recorder.runner()
        )
        #expect(result == 0)
    }

    @Test("shrinkSuffixStart respects upperBound - prefixLength as the max searchable start")
    func suffixStartRespectsUpperBound() {
        // Trap at index 12. Phase 1 (in real use) returns L=13.
        // maxStart = 16-13 = 3. All starts 0..3 cover index 12;
        // largest trapping start = 3.
        let recorder = TrapIndexRunner(trapIndex: 12)
        let result = InteractionShrinker.shrinkSuffixStart(
            failingSequenceIndex: 0,
            prefixLength: 13,
            upperBound: 16,
            runner: recorder.runner()
        )
        #expect(result == 3)
    }

    @Test("shrinkSuffixStart with maxStart=0 (prefixLength equals upperBound) returns 0")
    func suffixStartWhenWindowFillsBound() {
        // When prefixLength == upperBound there's no room to slide;
        // only start=0 is searchable.
        let recorder = TrapIndexRunner(trapIndex: 15)
        let result = InteractionShrinker.shrinkSuffixStart(
            failingSequenceIndex: 0,
            prefixLength: 16,
            upperBound: 16,
            runner: recorder.runner()
        )
        #expect(result == 0)
    }

    // MARK: - top-level shrink

    @Test("shrink produces both axes — drop-suffix then drop-prefix")
    func shrinkTwoPhase() {
        // Trap at index 7 of a length-16 sequence. Phase 1
        // (shrinkPrefix) finds prefixLength=8 (smallest length from 0
        // that contains index 7). Phase 2 (shrinkSuffixStart) with
        // length=8 finds the largest start where [start..start+8)
        // still covers 7, i.e. start=7 (window [7..15)).
        let recorder = TrapIndexRunner(trapIndex: 7)
        let result = InteractionShrinker.shrink(
            failingSequenceIndex: 99,
            upperBound: 16,
            runner: recorder.runner()
        )
        #expect(result.prefixLength == 8)
        #expect(result.suffixStart == 7)
    }

    @Test("shrink with trap at index 0 reduces to (start=0, length=1)")
    func shrinkTrapAtHead() {
        let recorder = TrapIndexRunner(trapIndex: 0)
        let result = InteractionShrinker.shrink(
            failingSequenceIndex: 0,
            upperBound: 16,
            runner: recorder.runner()
        )
        #expect(result.prefixLength == 1)
        #expect(result.suffixStart == 0)
    }

    @Test("ShrinkResult round-trips through Equatable")
    func shrinkResultEquatable() {
        let first = InteractionShrinker.ShrinkResult(suffixStart: 3, prefixLength: 5)
        let second = InteractionShrinker.ShrinkResult(suffixStart: 3, prefixLength: 5)
        let third = InteractionShrinker.ShrinkResult(suffixStart: 4, prefixLength: 5)
        #expect(first == second)
        #expect(first != third)
    }
}
