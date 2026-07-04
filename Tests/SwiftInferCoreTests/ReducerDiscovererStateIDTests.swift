import Foundation
@testable import SwiftInferCore
import Testing

/// Item 2 slice 3 — discovery-time capture of a `.tca` reducer's `State.ID`
/// type (`ReducerCandidate.stateIDTypeName`), used to resolve an
/// `IdentifiedActionOf<Child>` element against the child's id. Split out of
/// `ReducerDiscovererTCATests` to keep that suite under the `type_body_length`
/// cap.
@Suite("ReducerDiscoverer — State.ID capture (slice 3)")
struct ReducerDiscovererStateIDTests {

    @Test("State.ID type captured from an annotated id")
    func capturesAnnotatedStateID() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Row {
            @ObservableState
            struct State: Equatable, Identifiable {
                let id: UUID
                var count = 0
            }
            enum Action { case increment }
            var body: some Reducer<State, Action> {
                Reduce { state, action in .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Row.swift")
        #expect(result.count == 1)
        #expect(result[0].stateIDTypeName == "UUID")
    }

    @Test("State.ID inferred from a `let id = UUID()` initializer")
    func capturesInferredStateID() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Row {
            struct State: Equatable, Identifiable {
                let id = UUID()
                var count = 0
            }
            enum Action { case increment }
            var body: some Reducer<State, Action> {
                Reduce { state, action in .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Row.swift")
        #expect(result[0].stateIDTypeName == "UUID")
    }

    @Test("a State with no id captures nil")
    func capturesNoStateID() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Counter {
            struct State: Equatable { var count = 0 }
            enum Action { case increment }
            var body: some Reducer<State, Action> {
                Reduce { state, action in .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Counter.swift")
        #expect(result[0].stateIDTypeName == nil)
    }
}
