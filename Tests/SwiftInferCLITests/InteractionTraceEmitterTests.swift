import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V2.0 M8.C — assertions on InteractionTraceEmitter: pure text emit
// shape, the canonical `Tests/Generated/SwiftInferTraces/...` path,
// and disk-write round-trip.

@Suite("InteractionTraceEmitter — V2.0 M8.C trace-file emission")
struct InteractionTraceEmitterTests {

    private func candidate(
        location: String = "Sources/MyApp/Inbox.swift:42",
        enclosingTypeName: String? = nil,
        functionName: String = "reduce",
        signatureShape: ReducerSignatureShape = .stateActionReturnsState,
        stateTypeName: String = "AppState",
        actionTypeName: String = "AppAction",
        carrierKind: ReducerCarrierKind = .elmStyle,
        purity: ReducerPurity = .pure
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: location,
            enclosingTypeName: enclosingTypeName,
            functionName: functionName,
            signatureShape: signatureShape,
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName,
            carrierKind: carrierKind,
            purity: purity
        )
    }

    private func inputs(
        _ candidate: ReducerCandidate,
        userModuleName: String = "MyApp",
        sequenceCount: Int = 1_024
    ) -> InteractionTraceEmitter.Inputs {
        InteractionTraceEmitter.Inputs(
            candidate: candidate,
            userModuleName: userModuleName,
            sequenceCount: sequenceCount
        )
    }

    // MARK: - Header + import shape

    @Test("first line is the byte-stable header marker — tests can pin the format")
    func firstLineIsHeaderMarker() {
        let source = InteractionTraceEmitter.emit(inputs(candidate()))
        let firstLine = source.split(separator: "\n").first.map(String.init) ?? ""
        #expect(firstLine == InteractionTraceEmitter.traceHeaderMarker)
    }

    @Test("trace file imports Testing + user module + PropertyBased + PropertyLawKit")
    func traceFileImports() {
        let source = InteractionTraceEmitter.emit(inputs(candidate(), userModuleName: "Inbox"))
        #expect(source.contains("import Testing"))
        #expect(source.contains("import Inbox"))
        #expect(source.contains("import PropertyBased"))
        #expect(source.contains("import PropertyLawKit"))
    }

    @Test("trace declares an @Suite-wrapped struct + @Test replay function")
    func traceStructure() {
        let source = InteractionTraceEmitter.emit(inputs(candidate()))
        #expect(source.contains("@Suite(\"SwiftInferTraces — reduce\")"))
        #expect(source.contains("struct reduce_InteractionTrace {"))
        #expect(source.contains("@Test(\"Replay of failing action sequence (deterministic seed)\")"))
        #expect(source.contains("func replay() {"))
    }

    // MARK: - Verifier-loop shape

    @Test("trace loop drives ActionSequenceFactory + reducer-call (free function shape)")
    func traceLoopFreeFunction() {
        let source = InteractionTraceEmitter.emit(inputs(candidate(), sequenceCount: 8))
        #expect(source.contains("ActionSequenceFactory.actionSequence("))
        #expect(source.contains("forCaseIterable: AppAction.self"))
        #expect(source.contains("for _ in 0..<8 {"))
        #expect(source.contains("state = reduce(state, action)"))
    }

    @Test("trace loop uses the method-form reducer call for an enclosing type")
    func traceLoopMethodForm() {
        let source = InteractionTraceEmitter.emit(inputs(candidate(
            enclosingTypeName: "Inbox",
            functionName: "reduce",
            carrierKind: .generic
        )))
        #expect(source.contains("state = Inbox.reduce(state, action)"))
    }

    @Test("trace loop uses effect-discard form for `(S, A) -> (S, Effect<A>)`")
    func traceLoopEffectTupleShape() {
        let source = InteractionTraceEmitter.emit(inputs(candidate(
            signatureShape: .stateActionReturnsStateAndEffect,
            purity: .effectBearing
        )))
        #expect(source.contains("let (newState, _) = reduce(state, action)"))
        #expect(source.contains("state = newState"))
    }

    // MARK: - Seed determinism

    @Test("trace seed matches the verifier-stub seed for the same candidate")
    func traceSeedMatchesStubSeed() {
        let target = candidate()
        let traceSource = InteractionTraceEmitter.emit(inputs(target))
        let stubSeed = ActionSequenceStubEmitter.seedTuple(for: target)
        #expect(traceSource.contains("var rng = Xoshiro(seed: (\(stubSeed)))"))
    }

    // MARK: - Suite identifier

    @Test("suiteIdentifier replaces dots and dashes with underscores")
    func suiteIdentifierIsFilenameSafe() {
        let target = candidate(enclosingTypeName: "Inbox", functionName: "body")
        #expect(
            InteractionTraceEmitter.suiteIdentifier(for: target)
                == "Inbox_body_InteractionTrace"
        )
        let freeReducer = candidate()
        #expect(
            InteractionTraceEmitter.suiteIdentifier(for: freeReducer)
                == "reduce_InteractionTrace"
        )
    }

    // MARK: - Path resolution

    @Test("traceFilePath lands under Tests/Generated/SwiftInferTraces/<segment>/trace-replay.swift")
    func traceFilePathLayout() {
        let packageRoot = URL(fileURLWithPath: "/tmp/MyPackage", isDirectory: true)
        let target = candidate(enclosingTypeName: "Inbox", functionName: "body")
        let path = InteractionTraceEmitter.traceFilePath(
            packageRoot: packageRoot,
            candidate: target
        ).path
        #expect(path.hasSuffix(
            "Tests/Generated/SwiftInferTraces/Inbox_body/trace-replay.swift"
        ))
    }

    // MARK: - Disk-write round-trip

    // MARK: - V2.0 M8.D.1 — failing-sequence-index burn-then-replay

    @Test("M8.D.1: failingSequenceIndex=0 skips the burn loop and replays sequence 0")
    func traceWithZeroFailingIndexSkipsBurnLoop() {
        let target = candidate()
        let baseInputs = inputs(target)
        let withIndex = InteractionTraceEmitter.Inputs(
            candidate: baseInputs.candidate,
            userModuleName: baseInputs.userModuleName,
            sequenceCount: baseInputs.sequenceCount,
            failingSequenceIndex: 0
        )
        let source = InteractionTraceEmitter.emit(withIndex)
        // No burn loop when the very first sequence trapped.
        #expect(!source.contains("_ = generator.run(using: &rng)"))
        // Single replay step is present.
        #expect(source.contains("let actions = generator.run(using: &rng)"))
        #expect(source.contains("// Failing sequence index: 0"))
    }

    @Test("M8.D.1: failingSequenceIndex>0 burns the passing sequences before replay")
    func traceWithNonZeroFailingIndexBurnsPassingSequences() {
        let target = candidate()
        let withIndex = InteractionTraceEmitter.Inputs(
            candidate: target,
            userModuleName: "MyApp",
            failingSequenceIndex: 7
        )
        let source = InteractionTraceEmitter.emit(withIndex)
        #expect(source.contains("for _ in 0..<7 {"))
        #expect(source.contains("_ = generator.run(using: &rng)"))
        #expect(source.contains("// Failing sequence index: 7"))
        // The N-sequence loop posture from M8.C is gone — single
        // replay only.
        #expect(!source.contains("for _ in 0..<1024 {"))
    }

    @Test("M8.D.1: nil failingSequenceIndex preserves the M8.C all-sequences loop")
    func traceWithoutFailingIndexReplaysAllSequences() {
        let source = InteractionTraceEmitter.emit(inputs(candidate(), sequenceCount: 1_024))
        #expect(source.contains("for _ in 0..<1024 {"))
        #expect(!source.contains("// Failing sequence index:"))
    }

    // MARK: - V2.0 M8.D.3 — prefix-truncation in the replay body

    @Test("M8.D.3: minimumFailingPrefixLength truncates the replay action list")
    func traceWithPrefixLengthTruncates() {
        let withPrefix = InteractionTraceEmitter.Inputs(
            candidate: candidate(),
            userModuleName: "MyApp",
            failingSequenceIndex: 7,
            minimumFailingPrefixLength: 3
        )
        let source = InteractionTraceEmitter.emit(withPrefix)
        #expect(source.contains("let rawActions = generator.run(using: &rng)"))
        #expect(source.contains("let actions = Array(rawActions.prefix(3))"))
        #expect(source.contains("// Minimum failing prefix length: 3"))
    }

    @Test("M8.D.3: missing minimumFailingPrefixLength keeps the M8.D.1 full-replay shape")
    func traceWithoutPrefixLengthFullReplay() {
        let withIndex = InteractionTraceEmitter.Inputs(
            candidate: candidate(),
            userModuleName: "MyApp",
            failingSequenceIndex: 7,
            minimumFailingPrefixLength: nil
        )
        let source = InteractionTraceEmitter.emit(withIndex)
        #expect(source.contains("let actions = generator.run(using: &rng)"))
        #expect(!source.contains("// Minimum failing prefix length:"))
        #expect(!source.contains("rawActions.prefix("))
    }

    @Test("M8.D.3: prefix=0 still emits truncation (asserts empty actions path)")
    func traceWithPrefixZero() {
        let zeroPrefix = InteractionTraceEmitter.Inputs(
            candidate: candidate(),
            userModuleName: "MyApp",
            failingSequenceIndex: 0,
            minimumFailingPrefixLength: 0
        )
        let source = InteractionTraceEmitter.emit(zeroPrefix)
        #expect(source.contains("let actions = Array(rawActions.prefix(0))"))
        #expect(source.contains("// Minimum failing prefix length: 0"))
    }

    @Test("persist writes the trace file under the canonical layout")
    func persistRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InteractionTraceEmitterTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let path = try InteractionTraceEmitter.persist(
            inputs: inputs(candidate()),
            packageRoot: directory
        )
        #expect(FileManager.default.fileExists(atPath: path.path))
        let written = try String(contentsOf: path, encoding: .utf8)
        #expect(written.contains(InteractionTraceEmitter.traceHeaderMarker))
        #expect(written.contains("import Testing"))
    }
}

// V2.0 M8.D.4 — combined drop-prefix + drop-suffix slicing.
// Extension-grouped so the parent struct stays under SwiftLint's
// type_body_length cap.
extension InteractionTraceEmitterTests {

    @Test("M8.D.4: both suffixStart and prefix supplied — emits dropFirst+prefix combo")
    func traceWithBothSliceAxes() {
        let both = InteractionTraceEmitter.Inputs(
            candidate: candidate(),
            userModuleName: "MyApp",
            failingSequenceIndex: 7,
            minimumFailingPrefixLength: 5,
            minimumFailingSuffixStart: 3
        )
        let source = InteractionTraceEmitter.emit(both)
        #expect(source.contains("let actions = Array(rawActions.dropFirst(3).prefix(5))"))
        #expect(source.contains("// Minimum failing prefix length: 5"))
        #expect(source.contains("// Minimum failing suffix start: 3"))
    }

    @Test("M8.D.4: only suffixStart supplied — emits dropFirst-only slice")
    func traceWithSuffixStartOnly() {
        let onlyStart = InteractionTraceEmitter.Inputs(
            candidate: candidate(),
            userModuleName: "MyApp",
            failingSequenceIndex: 7,
            minimumFailingPrefixLength: nil,
            minimumFailingSuffixStart: 3
        )
        let source = InteractionTraceEmitter.emit(onlyStart)
        #expect(source.contains("let actions = Array(rawActions.dropFirst(3))"))
        #expect(source.contains("// Minimum failing suffix start: 3"))
    }

    @Test("M8.D.4: makeShrunkActionsExpression returns the right form for each axis combo")
    func makeShrunkActionsExpressionShape() {
        let bothPresent = InteractionTraceEmitter.makeShrunkActionsExpression(
            suffixStart: 2,
            prefixLength: 4
        )
        #expect(bothPresent.contains("Array(rawActions.dropFirst(2).prefix(4))"))
        let onlyPrefix = InteractionTraceEmitter.makeShrunkActionsExpression(
            suffixStart: nil,
            prefixLength: 4
        )
        #expect(onlyPrefix.contains("Array(rawActions.prefix(4))"))
        let onlyStart = InteractionTraceEmitter.makeShrunkActionsExpression(
            suffixStart: 2,
            prefixLength: nil
        )
        #expect(onlyStart.contains("Array(rawActions.dropFirst(2))"))
        let neither = InteractionTraceEmitter.makeShrunkActionsExpression(
            suffixStart: nil,
            prefixLength: nil
        )
        #expect(neither.contains("let actions = rawActions"))
    }
}
