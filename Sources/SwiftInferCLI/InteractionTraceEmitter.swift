import Foundation
import SwiftInferCore

/// V2.0 M8.C — emits a `@Test`-shape Swift source file that replays
/// a failing interaction-verify run. The trace file lives at
/// `Tests/Generated/SwiftInferTraces/<workdirSegment>/trace-replay.swift`
/// and runs as a standard Swift Testing regression on subsequent
/// `swift test` invocations.
///
/// **Trace shape.** The same verifier loop M3.B / M8.A emits, but
/// wrapped in a `@Suite` + `@Test` and using `#expect(false, ...)`
/// inside a Swift trap catch — since traps cannot be intercepted in
/// Swift, the trace instead asserts that the reducer + action-
/// sequence-generator from the recorded seed completes without a
/// trap. If the trap regresses, the test crashes (which Swift Testing
/// renders as a failure); if the user fixes the bug, the test passes.
///
/// **Determinism.** The trace re-creates the verifier's Xoshiro256**
/// state from the same seed tuple (`ActionSequenceStubEmitter.seedTuple`)
/// so the same action sequences are produced. PRD §16 #6.
///
/// **Shrinking deferred.** PRD §7.2 #3's drop-prefix / drop-suffix /
/// halving shrinking is a follow-up cycle — M8.C ships the un-shrunk
/// trace as the v1 regression artifact. Shrinking lands when the
/// failing-sequence-index recovery from the verifier's stderr is
/// wired (currently the M3.B stub doesn't print which sequence
/// trapped).
public enum InteractionTraceEmitter {

    /// V2.0 M8.C — inputs to the trace-file emit. `traceSuiteName` is
    /// auto-derived if not supplied; the caller may override for
    /// fixture-stable test output.
    public struct Inputs: Equatable, Sendable {
        public let candidate: ReducerCandidate
        public let userModuleName: String
        public let sequenceCount: Int
        public let lengthLowerBound: Int
        public let lengthUpperBound: Int

        public init(
            candidate: ReducerCandidate,
            userModuleName: String,
            sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
            lengthLowerBound: Int = 0,
            lengthUpperBound: Int = 16
        ) {
            self.candidate = candidate
            self.userModuleName = userModuleName
            self.sequenceCount = sequenceCount
            self.lengthLowerBound = lengthLowerBound
            self.lengthUpperBound = lengthUpperBound
        }
    }

    /// V2.0 M8.C — header marker (first non-blank line of trace
    /// output) so tests can pin the format without depending on
    /// emit-time variables.
    public static let traceHeaderMarker =
        "// swift-infer interaction-trace regression (V2.0 M8.C)"

    /// V2.0 M8.C — emit the trace file's Swift source. Pure: no
    /// disk I/O.
    public static func emit(_ inputs: Inputs) -> String {
        let reducerCall = ActionSequenceStubEmitter.makeReducerCall(inputs.candidate)
        let applyStep = ActionSequenceStubEmitter.makeApplyStep(
            shape: inputs.candidate.signatureShape,
            reducerCall: reducerCall
        )
        let seed = ActionSequenceStubEmitter.seedTuple(for: inputs.candidate)
        var lines: [String] = [
            traceHeaderMarker,
            "// Reducer: \(inputs.candidate.qualifiedName)",
            "// Carrier: \(inputs.candidate.carrierKind.rawValue)",
            "// Signature: \(inputs.candidate.signatureShape.rawValue)",
            "// Purity: \(inputs.candidate.purity.rawValue)",
            "// DO NOT EDIT — regenerated on each verify-interaction "
                + "`.measuredDefaultFails` outcome.",
            "",
            "import Testing",
            "import \(inputs.userModuleName)",
            "import PropertyBased",
            "import PropertyLawKit",
            "",
            "@Suite(\"SwiftInferTraces — \(inputs.candidate.qualifiedName)\")",
            "struct \(suiteIdentifier(for: inputs.candidate)) {",
            "    @Test(\"Replay of failing action sequence (deterministic seed)\")",
            "    func replay() {",
            "        var rng = Xoshiro(seed: (\(seed)))",
            "        let generator = ActionSequenceFactory.actionSequence(",
            "            forCaseIterable: \(inputs.candidate.actionTypeName).self,",
            "            length: \(inputs.lengthLowerBound)...\(inputs.lengthUpperBound)",
            "        )",
            "        for _ in 0..<\(inputs.sequenceCount) {",
            "            let actions = generator.run(using: &rng)",
            "            var state = \(inputs.candidate.stateTypeName)()",
            "            for action in actions {"
        ]
        for line in applyStep {
            lines.append("                \(line)")
        }
        lines.append("            }")
        lines.append("        }")
        lines.append("    }")
        lines.append("}")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Build the filesystem path for the trace file under
    /// `Tests/Generated/SwiftInferTraces/<workdirSegment>/trace-replay.swift`.
    /// `packageRoot` is the user's package root (typically the working
    /// directory passed to `verify-interaction`).
    public static func traceFilePath(
        packageRoot: URL,
        candidate: ReducerCandidate
    ) -> URL {
        packageRoot
            .appendingPathComponent("Tests")
            .appendingPathComponent("Generated")
            .appendingPathComponent("SwiftInferTraces")
            .appendingPathComponent(VerifyInteractionPipeline.workdirSegment(for: candidate))
            .appendingPathComponent("trace-replay.swift")
    }

    /// V2.0 M8.C — write the trace source to disk under the canonical
    /// `Tests/Generated/SwiftInferTraces/` layout. Returns the
    /// absolute path of the written file. Creates the directory
    /// hierarchy on demand.
    public static func persist(
        inputs: Inputs,
        packageRoot: URL
    ) throws -> URL {
        let source = emit(inputs)
        let path = traceFilePath(packageRoot: packageRoot, candidate: inputs.candidate)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try source.write(to: path, atomically: true, encoding: .utf8)
        return path
    }

    /// Filename-safe Swift identifier for the trace's `@Suite`-bearing
    /// struct. `Inbox.body` → `Inbox_body_InteractionTrace`; bare
    /// `reduce` → `reduce_InteractionTrace`.
    static func suiteIdentifier(for candidate: ReducerCandidate) -> String {
        let safe = candidate.qualifiedName
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        return "\(safe)_InteractionTrace"
    }
}
