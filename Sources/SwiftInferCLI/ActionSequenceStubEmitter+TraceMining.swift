import Foundation
import SwiftInferCore

// TestStore Trace Mining (Slice 2) — the `main()` loop tail: `var clean = 0`
// + the mined-trace replay block + the random `for sequenceIndex` loop +
// the outcome marker. Extracted from `ActionSequenceStubEmitter.assembleStub`
// so the parent file/function stay under SwiftLint's caps. Pure text emission.

extension ActionSequenceStubEmitter {

    /// The whole `main()` loop body below the RNG setup: the generator
    /// construction, clean counter, mined-trace replay (Slice 2), random
    /// sequence loop, and the outcome-marker print. Pre-indented to the
    /// `main()` interior.
    static func mainLoopLines(
        inputs: Inputs,
        stateInit: String,
        applyStep: [String],
        perStepCheck: [String],
        postLoopCheck: [String]
    ) -> [String] {
        var lines = generatorLines(inputs: inputs, isTCA: inputs.candidate.carrierKind == .tca)
        lines.append("        var clean = 0")
        lines.append(contentsOf: minedTraceReplayLines(
            inputs: inputs,
            stateInit: stateInit,
            applyStep: applyStep,
            perStepCheck: perStepCheck,
            postLoopCheck: postLoopCheck
        ))
        lines.append("        for sequenceIndex in 0..<\(inputs.sequenceCount) {")
        lines.append(contentsOf: makeIterationBody(
            stateInit: stateInit,
            applyStep: applyStep,
            perStepCheck: perStepCheck,
            postLoopCheck: postLoopCheck
        ))
        lines.append("        }")
        lines.append(
            "        print(\"\(cleanOutcomeMarker) totalRuns=\\(\(inputs.sequenceCount)) "
                + "clean=\\(clean)\")"
        )
        return lines
    }

    /// The mined-trace replay block, emitted between `var clean = 0` and the
    /// random `for sequenceIndex` loop. Each mined trace runs through the
    /// *same* per-step apply + invariant check + post-loop check as a
    /// generated sequence, so a developer-authored ordering that violates the
    /// invariant traps exactly as a random one would. Skipped when a shrink
    /// pin is active (`pinSequence != nil`) — the shrinker replays one
    /// *random* sequence and must not have the mined runs perturb its `clean`
    /// accounting. Returns `[]` for empty `seedTraces` (byte-identical output).
    static func minedTraceReplayLines(
        inputs: Inputs,
        stateInit: String,
        applyStep: [String],
        perStepCheck: [String],
        postLoopCheck: [String]
    ) -> [String] {
        guard !inputs.seedTraces.isEmpty else {
            return []
        }
        let elementType = inputs.candidate.actionTypeName
        let literals = inputs.seedTraces.map { trace in
            "                [" + trace.map { ".\($0)" }.joined(separator: ", ") + "],"
        }
        var lines: [String] = [
            "        // TestStore Trace Mining (Slice 2): developer-authored "
                + "orderings, checked before random generation.",
            "        if pinSequence == nil {",
            "            let minedTraces: [[\(elementType)]] = ["
        ]
        lines.append(contentsOf: literals)
        lines.append("            ]")
        lines.append("            for minedTrace in minedTraces {")
        lines.append("                var state = \(stateInit)")
        lines.append("                for action in minedTrace {")
        lines.append(contentsOf: applyStep.map { "                    \($0)" })
        lines.append(contentsOf: perStepCheck.map { "                    \($0)" })
        lines.append("                }")
        lines.append(contentsOf: postLoopCheck.map { "                \($0)" })
        lines.append("                clean += 1")
        lines.append("            }")
        lines.append("        }")
        return lines
    }
}
