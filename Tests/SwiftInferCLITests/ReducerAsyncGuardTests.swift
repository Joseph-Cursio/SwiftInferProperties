import Foundation
import Testing
@testable import SwiftInferCLI
@testable import SwiftInferCore

/// The async-reducer breadcrumb (collections/async workplan Phase 4): the
/// shape matchers never inspected effect specifiers, so an async reducer
/// becomes a candidate — and would fail the verify workdir *compile* with a
/// confusing await error. The pipeline now rejects it cleanly with the
/// error that names the deferred reducer-path async slice and asks for the
/// real-world example.
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
                #expect(error.description.contains("reducer-path verify emitter is currently synchronous"))

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
}
