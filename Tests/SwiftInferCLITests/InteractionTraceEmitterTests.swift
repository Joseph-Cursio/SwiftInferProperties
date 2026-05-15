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
        sequenceCount: Int = 1024
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
