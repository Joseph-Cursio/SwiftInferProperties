import Foundation
@testable import SwiftInferCore
import Testing

// Discovery resolves every reducer's Action type to its declaration among the
// scanned sources. Before this, only the TCA walk captured an Action's cases
// (`actionCases`), so every other carrier read as an open alphabet and
// `unknownActionIsNoOp` fired on a closed enum declared in the same file
// (found 2026-10-10 with the probe in `closedEnumInSameFileResolves`).

@Suite("ReducerDiscoverer — Action type resolution")
struct ReducerDiscovererActionTypeTests {

    private func onlyCandidate(_ source: String) throws -> ReducerCandidate {
        let result = ReducerDiscoverer.discover(source: source, file: "R.swift")
        try #require(result.count == 1)
        return result[0]
    }

    @Test("the 2026-10-10 probe: a closed enum in the same file resolves, CaseIterable or not")
    func closedEnumInSameFileResolves() throws {
        for conformances in ["Equatable", "Equatable, CaseIterable"] {
            let candidate = try onlyCandidate("""
            struct CounterState: Equatable { var count = 0; var total = 0; var items: [Int] = [] }
            enum CounterAction: \(conformances) { case increment, reset }
            func reduce(_ state: CounterState, _ action: CounterAction) -> CounterState {
                var s = state
                switch action {
                case .increment: s.count += 1
                case .reset: s = CounterState()
                }
                return s
            }
            """)
            #expect(candidate.carrierKind == .elmStyle)
            #expect(candidate.actionCases.isEmpty, "the TCA-only case capture is unchanged")
            #expect(candidate.actionTypeKind == .enum)
            #expect(candidate.hasClosedActionAlphabet)
        }
    }

    @Test("a protocol alphabet resolves open, declared or spelled `any`")
    func protocolAlphabetResolvesOpen() throws {
        let declared = try onlyCandidate("""
        protocol AppAction {}
        struct AppState: Equatable { var count = 0 }
        func reduce(_ state: AppState, _ action: AppAction) -> AppState { state }
        """)
        #expect(declared.actionTypeKind == .protocol)
        #expect(declared.hasClosedActionAlphabet == false)

        let existential = try onlyCandidate("""
        struct AppState: Equatable { var count = 0 }
        func reduce(_ state: AppState, _ action: any AppAction) -> AppState { state }
        """)
        #expect(existential.actionTypeKind == .protocol)
    }

    @Test("a type declared nowhere in the scan stays unresolved — ReSwift's imported `Action`")
    func importedActionStaysUnresolved() throws {
        let candidate = try onlyCandidate("""
        import ReSwift
        struct AppState: Equatable { var count = 0 }
        func appReducer(action: Action, state: AppState?) -> AppState { state ?? AppState() }
        """)
        #expect(candidate.carrierKind == .reSwift)
        #expect(candidate.actionTypeKind == .unresolved)
        #expect(candidate.hasClosedActionAlphabet == false)
    }

    @Test("a nested Action resolves through the enclosing scope, from the type or an extension of it")
    func nestedActionResolvesThroughScope() throws {
        let fromType = try onlyCandidate("""
        struct Feature {
            struct State: Equatable { var count = 0 }
            enum Action { case tap }
            static func reduce(_ state: State, _ action: Action) -> State { state }
        }
        """)
        #expect(fromType.actionTypeName == "Feature.Action")
        #expect(fromType.actionTypeKind == .enum)

        let fromExtension = try onlyCandidate("""
        struct Feature {
            struct State: Equatable { var count = 0 }
            enum Action { case tap }
        }
        extension Feature {
            static func reduce(_ state: State, _ action: Action) -> State { state }
        }
        """)
        #expect(fromExtension.actionTypeKind == .enum)
    }

    @Test("a bare name never borrows the kind of a same-named type nested elsewhere")
    func bareNameDoesNotMatchByLeaf() throws {
        // `Action` here is ReSwift's protocol; `Feature.Action` is unrelated.
        // A leaf-name index would call this reducer's alphabet closed.
        let candidate = try onlyCandidate("""
        struct Feature { enum Action { case tap } }
        struct AppState: Equatable { var count = 0 }
        func reduce(_ state: AppState, _ action: Action) -> AppState { state }
        """)
        #expect(candidate.actionTypeKind == .unresolved)
    }

    @Test("`Self` names the enclosing type — except in a protocol extension, where it names a conformer")
    func selfNamesTheEnclosingType() throws {
        func kind(_ opener: String) throws -> ActionTypeKind {
            try onlyCandidate("""
            enum Level { case low, high }
            struct Totals { var sum = 0 }
            protocol Mergeable {}
            \(opener) {
                static func merge(_ lhs: Self, _ rhs: Self) -> Self { lhs }
            }
            """).actionTypeKind
        }
        #expect(try kind("extension Level") == .enum)
        #expect(try kind("extension Totals") == .struct)
        #expect(try kind("extension Mergeable") == .unresolved)
    }

    @Test("a typealias is followed to what it names, in the alias's own scope")
    func typealiasIsFollowed() throws {
        let candidate = try onlyCandidate("""
        enum Messages { enum Msg { case tick } }
        typealias AppAction = Messages.Msg
        struct AppState: Equatable { var count = 0 }
        func reduce(_ state: AppState, _ action: AppAction) -> AppState { state }
        """)
        #expect(candidate.actionTypeKind == .enum)
    }

    @Test("a typealias cycle ends unresolved instead of looping")
    func typealiasCycleEndsUnresolved() throws {
        let candidate = try onlyCandidate("""
        typealias A = B
        typealias B = A
        struct AppState: Equatable { var count = 0 }
        func reduce(_ state: AppState, _ action: A) -> AppState { state }
        """)
        #expect(candidate.actionTypeKind == .unresolved)
    }

    @Test("two declarations of one path with different kinds resolve to neither")
    func conflictingDeclarationsStayUnresolved() throws {
        let candidate = try onlyCandidate("""
        #if os(Linux)
        enum AppAction { case tap }
        #else
        protocol AppAction {}
        #endif
        struct AppState: Equatable { var count = 0 }
        func reduce(_ state: AppState, _ action: AppAction) -> AppState { state }
        """)
        #expect(candidate.actionTypeKind == .unresolved)
    }

    @Test("a directory scan resolves an Action enum declared in a sibling file")
    func directoryScanResolvesAcrossFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReducerDiscovererActionTypeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("enum CounterAction { case increment, reset }\n".utf8)
            .write(to: directory.appendingPathComponent("Action.swift"))
        try Data("""
        struct CounterState: Equatable { var count = 0 }
        func reduce(_ state: CounterState, _ action: CounterAction) -> CounterState { state }
        """.utf8).write(to: directory.appendingPathComponent("Reducer.swift"))

        let result = try ReducerDiscoverer.discover(directory: directory)
        try #require(result.count == 1)
        #expect(result[0].actionTypeKind == .enum)
        // A single-file scan cannot see the sibling, and says so.
        let alone = try ReducerDiscoverer.discover(file: directory.appendingPathComponent("Reducer.swift"))
        #expect(alone.first?.actionTypeKind == .unresolved)
    }

    @Test("a TCA reducer's nested Action resolves too, alongside its captured cases")
    func tcaActionResolves() throws {
        let candidate = try onlyCandidate("""
        import ComposableArchitecture
        @Reducer
        struct Feature {
            struct State: Equatable { var count = 0 }
            enum Action { case tap }
            var body: some ReducerOf<Self> {
                Reduce { state, action in .none }
            }
        }
        """)
        #expect(candidate.carrierKind == .tca)
        #expect(candidate.actionTypeKind == .enum)
        #expect(candidate.actionCases.map(\.name) == ["tap"])
    }
}
