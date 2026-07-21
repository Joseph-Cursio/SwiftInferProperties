import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTestLifter
import Testing

// TestStore Trace Mining (Slices 2–3) — replay-then-extend emission +
// MinedTraceSelector (alphabet-driven selection, payload generalization,
// initial-state mining, Markov synthesis). Pure text / value assertions.

@Suite("TestStore Trace Mining — replay-then-extend + selection")
struct TraceMiningReplayTests {

    private typealias SeedTrace = ActionSequenceStubEmitter.SeedTrace

    private func candidate(
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
                SeedTrace(initialState: nil, actions: ["select"])
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

// Selector + end-to-end tests live in an extension so the suite body stays
// under SwiftLint's type_body_length cap (extension bodies are exempt; cycle
// 145 pattern).
extension TraceMiningReplayTests {

    // MARK: - MinedTraceSelector

    private func trace(
        reducer: String?,
        sent: [(String, [String])],
        initialState: String? = nil
    ) -> MinedActionTrace {
        MinedActionTrace(
            reducerTypeName: reducer,
            initialStateExpr: initialState,
            sent: sent.map { MinedAction(kind: .send, caseName: $0.0, argumentTexts: $0.1) },
            received: [],
            location: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
    }

    private func spec(_ name: String, _ params: [ActionParam] = []) -> ActionCaseSpec {
        ActionCaseSpec(name: name, parameters: params)
    }

    @Test("Selector keeps a payload-free trace joined by reducer type, in-alphabet")
    func selectorPayloadFree() {
        let selected = MinedTraceSelector.select(
            from: [trace(reducer: "Inbox", sent: [("dismiss", []), ("refresh", [])])],
            candidate: candidate(),
            alphabet: [spec("dismiss"), spec("refresh")]
        )
        #expect(selected == [SeedTrace(initialState: nil, actions: ["dismiss", "refresh"])])
    }

    @Test("Selector drops a trace whose reducer type doesn't match the candidate")
    func selectorReducerJoin() {
        let selected = MinedTraceSelector.select(
            from: [trace(reducer: "OtherFeature", sent: [("dismiss", [])])],
            candidate: candidate(),
            alphabet: [spec("dismiss")]
        )
        #expect(selected.isEmpty)
    }

    @Test("Slice 3b — payload-bearing trace is generalized to a canned literal")
    func selectorPayloadGeneralizedUnlabeled() {
        let selected = MinedTraceSelector.select(
            from: [trace(reducer: "Inbox", sent: [("select", ["a.id"])])],
            candidate: candidate(),
            alphabet: [spec("select", [ActionParam(label: nil, type: "Int")])]
        )
        #expect(selected == [SeedTrace(initialState: nil, actions: ["select(0)"])])
    }

    @Test("Slice 3b — a labeled payload keeps its label in the generalized call")
    func selectorPayloadGeneralizedLabeled() {
        let selected = MinedTraceSelector.select(
            from: [trace(reducer: "Inbox", sent: [("setCount", ["n"])])],
            candidate: candidate(),
            alphabet: [spec("setCount", [ActionParam(label: "value", type: "Int")])]
        )
        #expect(selected == [SeedTrace(initialState: nil, actions: ["setCount(value: 0)"])])
    }

    @Test("Slice 3b — a non-defaultable payload type drops the whole trace")
    func selectorNonDefaultablePayloadDropped() {
        let selected = MinedTraceSelector.select(
            from: [trace(reducer: "Inbox", sent: [("setColor", ["c"])])],
            candidate: candidate(),
            alphabet: [spec("setColor", [ActionParam(label: nil, type: "Color")])]
        )
        #expect(selected.isEmpty)
    }

    @Test("Selector drops a trace referencing a stale (out-of-alphabet) case")
    func selectorStaleCaseGuard() {
        let selected = MinedTraceSelector.select(
            from: [trace(reducer: "Inbox", sent: [("dismiss", []), ("goneCase", [])])],
            candidate: candidate(),
            alphabet: [spec("dismiss")]
        )
        #expect(selected.isEmpty)
    }

    @Test("Empty alphabet → nothing selected")
    func selectorEmptyAlphabet() {
        let selected = MinedTraceSelector.select(
            from: [trace(reducer: "Inbox", sent: [("dismiss", [])])],
            candidate: candidate(),
            alphabet: []
        )
        #expect(selected.isEmpty)
    }

    // MARK: - Slice 3c: self-contained initial state

    @Test("Self-contained initial state (literal args) is preserved")
    func selfContainedInitialStateKept() {
        #expect(MinedTraceSelector.selfContainedInitialState("Feature.State(count: 3)")
            == "Feature.State(count: 3)")
        #expect(MinedTraceSelector.selfContainedInitialState("Feature.State()")
            == "Feature.State()")
    }

    @Test("Fixture-referencing initial state (local binding) is dropped")
    func fixtureReferencingInitialStateDropped() {
        #expect(MinedTraceSelector.selfContainedInitialState("Feature.State(items: [a, b])") == nil)
    }

    @Test("Selector attaches a self-contained mined initial state to the seed trace")
    func selectorAttachesInitialState() {
        let mined = trace(reducer: "Inbox", sent: [("dismiss", [])], initialState: "AppState(count: 3)")
        let selected = MinedTraceSelector.select(
            from: [mined],
            candidate: candidate(),
            alphabet: [spec("dismiss")]
        )
        #expect(selected == [SeedTrace(initialState: "AppState(count: 3)", actions: ["dismiss"])])
    }

    // MARK: - Slice 3e: Markov synthesis

    @Test("Markov synthesis recombines observed transitions into a novel ordering")
    func markovRecombines() {
        let input = [
            SeedTrace(initialState: nil, actions: ["a", "b"]),
            SeedTrace(initialState: nil, actions: ["b", "c"])
        ]
        let synthesized = MinedTraceSelector.markovSynthesized(from: input)
        // Starting from 'a', follow a→b then b→c → [a, b, c] (novel, not an input).
        #expect(synthesized.contains(SeedTrace(initialState: nil, actions: ["a", "b", "c"])))
    }

    @Test("Markov synthesis via select(includeMarkov:) appends the synthesized trace")
    func markovViaSelect() {
        let selected = MinedTraceSelector.select(
            from: [
                trace(reducer: "Inbox", sent: [("a", []), ("b", [])]),
                trace(reducer: "Inbox", sent: [("b", []), ("c", [])])
            ],
            candidate: candidate(),
            alphabet: [spec("a"), spec("b"), spec("c")],
            includeMarkov: true
        )
        #expect(selected.contains(SeedTrace(initialState: nil, actions: ["a", "b", "c"])))
    }

    // MARK: - End-to-end wiring (discover + scan alphabet + mine + emit)

    @Test("resolveEmitAndSeed mines a sibling TestStore test and injects it into the stub")
    func wiringInjectsMinedTraces() throws {
        let directory = try makeFixtureDirectory(name: "TraceMiningWiring")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Feature.swift",
            contents: """
            import ComposableArchitecture
            @Reducer
            struct Feature {
                @ObservableState struct State: Equatable { var isOpen = false }
                enum Action { case close, refresh }
                var body: some Reducer<State, Action> {
                    Reduce { state, action in .none }
                }
            }
            """
        )
        try writeFile(
            in: directory,
            relativePath: "Tests/MyAppTests",
            named: "FeatureTests.swift",
            contents: """
            import ComposableArchitecture
            import XCTest
            final class FeatureTests: XCTestCase {
                func testFlow() async {
                    let store = TestStore(initialState: Feature.State()) { Feature() }
                    await store.send(.close)
                    await store.send(.refresh)
                }
            }
            """
        )
        let seeded = try VerifyInteractionPipeline.resolveEmitAndSeed(
            target: "MyApp",
            pinRaw: "Feature.body",
            workingDirectory: directory
        )
        #expect(seeded.candidate.carrierKind == .tca)
        #expect(seeded.seedTraceCount == 1)
        let header = "let minedTraces: [(state: Feature.State, actions: [Feature.Action])] = ["
        #expect(seeded.stubSource.contains(header))
        #expect(seeded.stubSource.contains("(Feature.State(), [.close, .refresh]),"))
    }

    @Test("resolveEmitAndSeed with no Tests dir yields no seed traces (byte-identical path)")
    func wiringNoTestsDirNoSeeds() throws {
        let directory = try makeFixtureDirectory(name: "TraceMiningNoTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Feature.swift",
            contents: """
            import ComposableArchitecture
            @Reducer
            struct Feature {
                @ObservableState struct State: Equatable { var isOpen = false }
                enum Action { case close, refresh }
                var body: some Reducer<State, Action> {
                    Reduce { state, action in .none }
                }
            }
            """
        )
        let seeded = try VerifyInteractionPipeline.resolveEmitAndSeed(
            target: "MyApp",
            pinRaw: "Feature.body",
            workingDirectory: directory
        )
        #expect(seeded.seedTraceCount == 0)
        #expect(!seeded.stubSource.contains("minedTraces"))
    }

    // MARK: - Fixture helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TraceMiningReplayTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeFile(
        in directory: URL,
        relativePath: String,
        named name: String,
        contents: String
    ) throws {
        let dir = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: dir.appendingPathComponent(name))
    }
}
