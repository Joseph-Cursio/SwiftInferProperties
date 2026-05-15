import Foundation
import Testing
@testable import SwiftInferCLI

// V2.0 M8.D.3 — binary-search shrinker correctness. Pure: every
// test injects a synthetic `Runner` whose closure returns a fixed
// exit-code-bearing rule, exercising the shrinker without spawning
// a real binary.

@Suite("InteractionShrinker — V2.0 M8.D.3 binary-search shrinker")
struct InteractionShrinkerTests {

    /// Runner that traps iff `prefixLength >= threshold`. Models the
    /// canonical case: "the trap needs at least N actions in the
    /// sequence." Records every (sequence, prefix) pair it sees so
    /// tests can assert on the search path.
    private final class ThresholdRunner: @unchecked Sendable {
        let threshold: Int
        var invocations: [(sequenceIndex: Int, prefixLength: Int)] = []

        init(threshold: Int) {
            self.threshold = threshold
        }

        func runner() -> InteractionShrinker.Runner {
            InteractionShrinker.Runner { [self] sequenceIndex, prefixLength in
                invocations.append((sequenceIndex, prefixLength))
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
