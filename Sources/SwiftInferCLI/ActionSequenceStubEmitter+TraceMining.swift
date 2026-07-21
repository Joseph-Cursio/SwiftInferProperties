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
    /// invariant traps exactly as a random one would. Each trace carries its
    /// own initial State (Slice 3c) — a mined `TestStore(initialState:)` when
    /// self-contained, else the reducer default. Skipped when a shrink pin is
    /// active (`pinSequence != nil`) — the shrinker replays one *random*
    /// sequence and must not have the mined runs perturb its `clean`
    /// accounting. With `prefixBias` (Slice 3d) each mined ordering is *also*
    /// run as a prefix extended by a random tail. Returns `[]` for empty
    /// `seedTraces` (byte-identical output).
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
        let stateType = inputs.candidate.stateTypeName
        let actionType = inputs.candidate.actionTypeName
        let entries = inputs.seedTraces.map { trace -> String in
            let state = trace.initialState ?? stateInit
            let acts = trace.actions.map { ".\($0)" }.joined(separator: ", ")
            return "                (\(state), [\(acts)]),"
        }
        var lines: [String] = [
            "        // TestStore Trace Mining (Slice 3): developer-authored "
                + "orderings, checked before random generation.",
            "        if pinSequence == nil {",
            "            let minedTraces: [(state: \(stateType), actions: [\(actionType)])] = ["
        ]
        lines.append(contentsOf: entries)
        lines.append("            ]")
        lines.append(contentsOf: replayLoopLines(
            applyStep: applyStep, perStepCheck: perStepCheck, postLoopCheck: postLoopCheck
        ))
        if inputs.prefixBias {
            lines.append(contentsOf: prefixBiasLines(
                applyStep: applyStep, perStepCheck: perStepCheck, postLoopCheck: postLoopCheck
            ))
        }
        lines.append("        }")
        return lines
    }

    /// The verbatim mode-(a) replay loop over `minedTraces` (12-space indent).
    private static func replayLoopLines(
        applyStep: [String],
        perStepCheck: [String],
        postLoopCheck: [String]
    ) -> [String] {
        var lines = [
            "            for minedTrace in minedTraces {",
            "                var state = minedTrace.state",
            "                for action in minedTrace.actions {"
        ]
        lines.append(contentsOf: applyStep.map { "                    \($0)" })
        lines.append(contentsOf: perStepCheck.map { "                    \($0)" })
        lines.append("                }")
        lines.append(contentsOf: postLoopCheck.map { "                \($0)" })
        lines.append("                clean += 1")
        lines.append("            }")
        return lines
    }

    /// Slice 3d — mode (b) prefix-biased loop: each mined ordering as a prefix,
    /// extended by a random tail from the same generator, so verification
    /// starts from human-plausible states and explores outward.
    private static func prefixBiasLines(
        applyStep: [String],
        perStepCheck: [String],
        postLoopCheck: [String]
    ) -> [String] {
        var lines = [
            "            for minedTrace in minedTraces {",
            "                var state = minedTrace.state",
            "                let tail = generator.run(using: &rng)",
            "                for action in minedTrace.actions + tail {"
        ]
        lines.append(contentsOf: applyStep.map { "                    \($0)" })
        lines.append(contentsOf: perStepCheck.map { "                    \($0)" })
        lines.append("                }")
        lines.append(contentsOf: postLoopCheck.map { "                \($0)" })
        lines.append("                clean += 1")
        lines.append("            }")
        return lines
    }
}
