import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// Regression guard for the namespace-reducer qualification fix.
///
/// A reducer that is a method on a namespace type (`enum SyncReducer { static func
/// reduce(_:_:) }`) whose State/Action are TOP-LEVEL types was silently missing its
/// witness families (idempotence / conservation / cardinality / …): discovery's
/// `qualifyIfNested` correctly left `SyncAction` bare, but the `ReducerCandidate`
/// `qualify()` computed property then re-prepended the namespace →
/// `"SyncReducer.SyncAction"`, which the witness detectors' type-stack suffix match
/// never matched against the top-level `["SyncAction"]`. Removing the redundant
/// prepend (cycle-109's `qualifyIfNested` already qualifies NESTED names at
/// discovery) fixes it without reintroducing the cycle-87 cross-contamination.
@Suite
struct NamespaceReducerQualificationTests {

    private func writeFixture(_ source: String) throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("NamespaceReducerQual-\(UUID().uuidString)")
        let sources = temp.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data(source.utf8).write(to: sources.appendingPathComponent("Reducer.swift"))
        return temp
    }

    @Test("A namespace reducer with top-level State/Action surfaces its idempotence witness")
    func topLevelStateActionSurfacesIdempotence() throws {
        let temp = try writeFixture("""
        struct SyncState: Equatable { var count = 0 }
        enum SyncAction: CaseIterable { case bump, reset }

        enum SyncReducer {
            static func reduce(_ state: SyncState, _ action: SyncAction) -> SyncState { state }
        }
        """)
        defer { try? FileManager.default.removeItem(at: temp) }

        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            target: "App",
            workingDirectory: temp
        )
        let idempotence = suggestions.filter {
            $0.reducerQualifiedName == "SyncReducer.reduce" && $0.family == .idempotence
        }
        // `.reset` is an idempotence witness verb; before the fix the over-qualified
        // action name meant zero idempotence witnesses fired for this shape.
        #expect(idempotence.contains { $0.predicate == ".reset" })
    }

    @Test("Two namespace reducers sharing nested names do not cross-contaminate (real discovery)")
    func twoReducersDoNotCrossContaminate() throws {
        // The cycle-87 concern, exercised through REAL discovery rather than hand-built
        // bare-name candidates: `qualifyIfNested` qualifies each nested Action to
        // `AReducer.Action` / `BReducer.Action`, so each reducer's idempotence witness
        // scopes to its own actions — `.reset` under A, `.clear` under B, never crossed.
        let temp = try writeFixture("""
        struct AReducer {
            struct State: Equatable { var count = 0 }
            enum Action: CaseIterable { case add, reset }
            func reduce(_ state: State, _ action: Action) -> State { state }
        }
        struct BReducer {
            struct State: Equatable { var count = 0 }
            enum Action: CaseIterable { case push, clear }
            func reduce(_ state: State, _ action: Action) -> State { state }
        }
        """)
        defer { try? FileManager.default.removeItem(at: temp) }

        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            target: "App",
            workingDirectory: temp
        )
        let idempotence = suggestions.filter { $0.family == .idempotence }
        let byReducer = Dictionary(grouping: idempotence, by: \.reducerQualifiedName)
        let aPredicates = Set((byReducer["AReducer.reduce"] ?? []).map(\.predicate))
        let bPredicates = Set((byReducer["BReducer.reduce"] ?? []).map(\.predicate))
        #expect(aPredicates == [".reset"])
        #expect(bPredicates == [".clear"])
    }
}
