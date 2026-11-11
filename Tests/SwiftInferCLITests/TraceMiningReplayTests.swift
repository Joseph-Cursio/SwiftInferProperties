import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// TestStore Trace Mining (Slices 2–3) — replay-then-extend emission +
// MinedTraceSelector (alphabet-driven selection, payload generalization,
// initial-state mining, Markov synthesis). Pure text / value assertions.

@Suite("TestStore Trace Mining — replay-then-extend + selection")
struct TraceMiningReplayTests {

    typealias SeedTrace = ActionSequenceStubEmitter.SeedTrace

    func candidate(
        enclosingTypeName: String? = "Inbox",
        stateTypeName: String = "AppState",
        actionTypeName: String = "AppAction",
        carrierKind: ReducerCarrierKind = .elmStyle
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/MyApp/Inbox.swift:42",
            enclosingTypeName: enclosingTypeName,
            functionName: "reduce",
            signatureShape: .stateActionReturnsState,
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName,
            carrierKind: carrierKind
        )
    }

    private func inputs(
        _ candidate: ReducerCandidate,
        seedTraces: [SeedTrace] = [],
        prefixBias: Bool = false
    ) -> ActionSequenceStubEmitter.Inputs {
        ActionSequenceStubEmitter.Inputs(
            candidate: candidate,
            userModuleName: "MyApp",
            seedTraces: seedTraces,
            prefixBias: prefixBias
        )
    }

    // MARK: - Emitter: byte-identical when nothing is mined

    @Test("Empty seedTraces → output is byte-identical to the no-seed stub")
    func emptySeedTracesByteIdentical() throws {
        let base = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        let seeded = try ActionSequenceStubEmitter.emit(inputs(candidate(), seedTraces: []))
        #expect(base == seeded)
        #expect(!base.contains("minedTraces"))
    }

    // MARK: - Emitter: replay block

    @Test("Non-empty seedTraces → emits the tuple minedTraces literal + replay loop")
    func seedTracesEmitReplayBlock() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(
            candidate(),
            seedTraces: [
                SeedTrace(initialState: nil, actions: ["dismiss", "refresh"]),
                SeedTrace(initialState: nil, actions: ["select"]),
            ]
        ))
        #expect(source.contains("let minedTraces: [(state: AppState, actions: [AppAction])] = ["))
        #expect(source.contains("(AppState(), [.dismiss, .refresh]),"))
        #expect(source.contains("(AppState(), [.select]),"))
        #expect(source.contains("for minedTrace in minedTraces {"))
        #expect(source.contains("for action in minedTrace.actions {"))
        #expect(source.contains("state = Inbox.reduce(state, action)"))
        // Mined block precedes the random loop (replay-then-extend order).
        let minedIndex = try #require(source.range(of: "minedTraces"))
        let randomIndex = try #require(source.range(of: "for sequenceIndex in"))
        #expect(minedIndex.lowerBound < randomIndex.lowerBound)
    }

    @Test("Slice 3c — a mined initial state is used verbatim in the tuple entry")
    func initialStateEmitted() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(
            candidate(),
            seedTraces: [SeedTrace(initialState: "AppState(count: 3)", actions: ["dismiss"])]
        ))
        #expect(source.contains("(AppState(count: 3), [.dismiss]),"))
    }

    @Test("Slice 3d — prefixBias emits the prefix + random-tail loop")
    func prefixBiasEmitsTailLoop() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(
            candidate(),
            seedTraces: [SeedTrace(initialState: nil, actions: ["dismiss"])],
            prefixBias: true
        ))
        #expect(source.contains("let tail = generator.run(using: &rng)"))
        #expect(source.contains("for action in minedTrace.actions + tail {"))
    }

    @Test("prefixBias off → no tail loop emitted")
    func noPrefixBiasNoTailLoop() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(
            candidate(),
            seedTraces: [SeedTrace(initialState: nil, actions: ["dismiss"])]
        ))
        #expect(!source.contains("minedTrace.actions + tail"))
    }

    @Test("Replay block is guarded by the shrink pin")
    func replaySkippedUnderShrinkPin() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(
            candidate(),
            seedTraces: [SeedTrace(initialState: nil, actions: ["dismiss"])]
        ))
        let guardRange = try #require(source.range(of: "if pinSequence == nil {"))
        let minedRange = try #require(source.range(of: "let minedTraces"))
        #expect(guardRange.lowerBound < minedRange.lowerBound)
    }
}
