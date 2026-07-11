import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// The async-reducer guard (collections/async workplan Phase 4): the
/// shape matchers never inspected effect specifiers, so an async reducer
/// becomes a candidate — and would fail the verify workdir *compile* with a
/// confusing await error. Bare async is rejected cleanly (seeded replays
/// would be nondeterministic); the clock-determinism claim admits it to
/// the async emit path (`ReducerAsyncSliceTests`).
@Suite
struct ReducerAsyncGuardTests {

    @Test("resolveAndEmit against an async reducer throws .asyncReducer")
    func asyncReducerRejectedCleanly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReducerAsyncGuard-\(UUID().uuidString)")
        let sources = directory.appendingPathComponent("Sources/MyApp")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        enum Counter {
            static func reduce(_ s: AppState, _ a: AppAction) async -> AppState {
                s
            }
        }
        """.write(
            to: sources.appendingPathComponent("Reducer.swift"),
            atomically: true,
            encoding: .utf8
        )
        do {
            _ = try VerifyInteractionPipeline.resolveAndEmit(
                target: "MyApp",
                workingDirectory: directory
            )
            Issue.record("expected .asyncReducer error")
        } catch let error as VerifyInteractionError {
            switch error {
            case let .asyncReducer(reducer):
                #expect(reducer == "Counter.reduce")
                #expect(error.description.contains("async without the clock-determinism claim"))
                #expect(error.description.contains("@ClockDeterministic"))

            default:
                Issue.record("expected .asyncReducer, got \(error)")
            }
        }
    }

    @Test("Candidates persisted before the isAsync field still decode")
    func decodesLegacyCandidateWithoutFlag() throws {
        let candidate = ReducerCandidate(
            location: "Reducer.swift:2",
            enclosingTypeName: "Counter",
            functionName: "reduce",
            signatureShape: .stateActionReturnsState,
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            isAsync: true
        )
        // Simulate a legacy record: encode, strip the new key, decode.
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(candidate)
        ) as? [String: Any] ?? [:]
        json.removeValue(forKey: "isAsync")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ReducerCandidate.self, from: legacyData)
        #expect(decoded.isAsync == false)
        #expect(decoded.functionName == "reduce")
    }

    @Test("Resolver enrichment preserves the isAsync flag")
    func replacingActionCasesPreservesFlag() {
        let candidate = ReducerCandidate(
            location: "Reducer.swift:2",
            enclosingTypeName: "Counter",
            functionName: "reduce",
            signatureShape: .stateActionReturnsState,
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            isAsync: true
        )
        #expect(candidate.replacingActionCases([]).isAsync)
    }

    @Test("Discovery captures the clock-determinism claim on the declaration")
    func discoveryCapturesClockDeterminismClaim() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReducerClockClaim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        enum Counter {
            /// @lint.determinism clock_deterministic
            static func reduce(_ s: AppState, _ a: AppAction) async -> AppState {
                s
            }

            static func reduceBare(_ s: AppState, _ a: AppAction) async -> AppState {
                s
            }
        }
        """.write(
            to: directory.appendingPathComponent("Reducer.swift"),
            atomically: true,
            encoding: .utf8
        )
        let candidates = try ReducerDiscoverer.discover(directory: directory)
        let annotated = try #require(candidates.first { $0.functionName == "reduce" })
        let bare = try #require(candidates.first { $0.functionName == "reduceBare" })
        #expect(annotated.isAsync)
        #expect(annotated.isClockDeterministic)
        #expect(bare.isAsync)
        #expect(bare.isClockDeterministic == false)
    }

    @Test("Candidates persisted before the isClockDeterministic field still decode")
    func decodesLegacyCandidateWithoutClockClaim() throws {
        let candidate = ReducerCandidate(
            location: "Reducer.swift:2",
            enclosingTypeName: "Counter",
            functionName: "reduce",
            signatureShape: .stateActionReturnsState,
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            isAsync: true,
            isClockDeterministic: true
        )
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(candidate)
        ) as? [String: Any] ?? [:]
        json.removeValue(forKey: "isClockDeterministic")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ReducerCandidate.self, from: legacyData)
        #expect(decoded.isClockDeterministic == false)
        #expect(decoded.isAsync)
    }

    @Test("Resolver enrichment preserves the isClockDeterministic flag")
    func replacingActionCasesPreservesClockClaim() {
        let candidate = ReducerCandidate(
            location: "Reducer.swift:2",
            enclosingTypeName: "Counter",
            functionName: "reduce",
            signatureShape: .stateActionReturnsState,
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            isAsync: true,
            isClockDeterministic: true
        )
        #expect(candidate.replacingActionCases([]).isClockDeterministic)
    }
}
