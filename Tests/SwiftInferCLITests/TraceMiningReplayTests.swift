import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTestLifter
import Testing

// TestStore Trace Mining (Slice 2) — replay-then-extend emission + the
// MinedTraceSelector filters. Pure text / value assertions: no subprocess.

@Suite("TestStore Trace Mining — Slice 2 replay-then-extend")
struct TraceMiningReplayTests {

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
        seedTraces: [[String]] = []
    ) -> ActionSequenceStubEmitter.Inputs {
        ActionSequenceStubEmitter.Inputs(
            candidate: candidate,
            userModuleName: "MyApp",
            seedTraces: seedTraces
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

    // MARK: - Emitter: replay block when traces are present

    @Test("Non-empty seedTraces → emits the minedTraces literal + replay loop")
    func seedTracesEmitReplayBlock() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(
            candidate(),
            seedTraces: [["dismiss", "refresh"], ["select"]]
        ))
        // The literal array is typed to the Action and lists dotted cases.
        #expect(source.contains("let minedTraces: [[AppAction]] = ["))
        #expect(source.contains("[.dismiss, .refresh],"))
        #expect(source.contains("[.select],"))
        // Replayed through the same apply loop, gated behind the shrink pin.
        #expect(source.contains("for minedTrace in minedTraces {"))
        #expect(source.contains("for action in minedTrace {"))
        // The mined loop reuses the same apply step as the random loop.
        #expect(source.contains("state = Inbox.reduce(state, action)"))
        // Mined block precedes the random loop (replay-then-extend order).
        let minedIndex = try #require(source.range(of: "minedTraces"))
        let randomIndex = try #require(source.range(of: "for sequenceIndex in"))
        #expect(minedIndex.lowerBound < randomIndex.lowerBound)
    }

    @Test("Replay block is guarded by the shrink pin so a pin run skips mined traces")
    func replaySkippedUnderShrinkPin() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(
            candidate(),
            seedTraces: [["dismiss"]]
        ))
        // The `if pinSequence == nil {` guard wraps the mined block.
        let guardRange = try #require(source.range(of: "if pinSequence == nil {"))
        let minedRange = try #require(source.range(of: "let minedTraces"))
        #expect(guardRange.lowerBound < minedRange.lowerBound)
    }

    // MARK: - MinedTraceSelector

    private func trace(
        reducer: String?,
        sent: [(String, [String])]
    ) -> MinedActionTrace {
        MinedActionTrace(
            reducerTypeName: reducer,
            initialStateExpr: nil,
            sent: sent.map { MinedAction(kind: .send, caseName: $0.0, argumentTexts: $0.1) },
            received: [],
            location: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
    }

    private func tcaCandidate(cases: [String]) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/MyApp/Feature.swift:1",
            enclosingTypeName: "Feature",
            functionName: "body",
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: "Feature.State",
            actionTypeName: "Feature.Action",
            carrierKind: .tca,
            actionCases: cases.map { ActionCaseInfo(name: $0, payloadTypes: []) }
        )
    }

    @Test("Selector keeps a payload-free trace joined by reducer type, in-alphabet")
    func selectorHappyPath() {
        let candidate = tcaCandidate(cases: ["dismiss", "refresh", "select"])
        let traces = [trace(reducer: "Feature", sent: [("dismiss", []), ("refresh", [])])]
        let selected = MinedTraceSelector.payloadFreeSeedTraces(from: traces, candidate: candidate)
        #expect(selected == [["dismiss", "refresh"]])
    }

    @Test("Selector drops a trace whose reducer type doesn't match the candidate")
    func selectorReducerJoin() {
        let candidate = tcaCandidate(cases: ["dismiss"])
        let traces = [trace(reducer: "OtherFeature", sent: [("dismiss", [])])]
        #expect(MinedTraceSelector.payloadFreeSeedTraces(from: traces, candidate: candidate).isEmpty)
    }

    @Test("Selector drops a payload-bearing trace (args not reconstructible)")
    func selectorPayloadBearingDropped() {
        let candidate = tcaCandidate(cases: ["select"])
        let traces = [trace(reducer: "Feature", sent: [("select", ["a.id"])])]
        #expect(MinedTraceSelector.payloadFreeSeedTraces(from: traces, candidate: candidate).isEmpty)
    }

    @Test("Selector drops a trace referencing a stale (out-of-alphabet) case")
    func selectorStaleCaseGuard() {
        let candidate = tcaCandidate(cases: ["dismiss"])
        let traces = [trace(reducer: "Feature", sent: [("dismiss", []), ("renamedGone", [])])]
        #expect(MinedTraceSelector.payloadFreeSeedTraces(from: traces, candidate: candidate).isEmpty)
    }

    @Test("Selector yields nothing for a non-.tca candidate (no captured alphabet)")
    func selectorNonTCAExcluded() {
        // Generic carrier: alphabet not captured at discovery → no seeding yet.
        let generic = candidate(carrierKind: .elmStyle)
        let traces = [trace(reducer: "Inbox", sent: [("dismiss", [])])]
        #expect(MinedTraceSelector.payloadFreeSeedTraces(from: traces, candidate: generic).isEmpty)
    }

    // MARK: - End-to-end wiring (discover + mine + select + emit; no subprocess)

    @Test("resolveEmitAndSeed mines a sibling TestStore test and injects it into the stub")
    func wiringInjectsMinedTraces() throws {
        let directory = try makeFixtureDirectory(name: "TraceMiningWiring")
        defer { try? FileManager.default.removeItem(at: directory) }
        // A real @Reducer the TCA discoverer recognizes (payload-free Action).
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
        // A sibling TestStore test whose ordering the extractor mines.
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
        #expect(seeded.stubSource.contains("let minedTraces: [[Feature.Action]] = ["))
        #expect(seeded.stubSource.contains("[.close, .refresh],"))
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
