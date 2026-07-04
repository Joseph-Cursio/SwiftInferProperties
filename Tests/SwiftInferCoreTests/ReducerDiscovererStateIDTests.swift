import Foundation
@testable import SwiftInferCore
import Testing

/// Item 2 slices 3/4 — discovery-time State introspection on a `.tca` reducer:
/// the `State.ID` type (`stateIDTypeName`, slice 3, for `IdentifiedActionOf`)
/// and the `@ObservableState` bindable stored `var` fields (`stateFields`,
/// slice 4, for `BindingAction`). Split out of `ReducerDiscovererTCATests` to
/// keep that suite under the `type_body_length` cap.
@Suite("ReducerDiscoverer — State introspection (slices 3/4)")
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

    // MARK: - slice 4: @ObservableState bindable fields

    @Test("bindable stored var fields captured (annotation + literal inference)")
    func capturesBindableFields() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Form {
            @ObservableState
            struct State: Equatable {
                var text = ""
                var count = 0
                var toggleIsOn = false
                var sliderValue = 5.0
                var name: String = "x"
            }
            enum Action: BindableAction { case binding(BindingAction<State>) }
            var body: some Reducer<State, Action> {
                BindingReducer()
                Reduce { _, _ in .none }
            }
        }
        """
        let fields = ReducerDiscoverer.discover(source: source, file: "Form.swift")[0].stateFields
        #expect(fields.map(\.name) == ["text", "count", "toggleIsOn", "sliderValue", "name"])
        #expect(fields.map(\.typeName) == ["String", "Int", "Bool", "Double", "String"])
    }

    @Test("let / static / computed / attributed fields excluded")
    func excludesNonBindableFields() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Form {
            @ObservableState
            struct State: Equatable {
                var text = ""
                let id = ""
                static var shared = 0
                var computed: Int { 1 }
                @Presents var alert: AlertState<Never>?
            }
            enum Action: BindableAction { case binding(BindingAction<State>) }
            var body: some Reducer<State, Action> { BindingReducer(); Reduce { _, _ in .none } }
        }
        """
        let fields = ReducerDiscoverer.discover(source: source, file: "Form.swift")[0].stateFields
        #expect(fields.map(\.name) == ["text"])
    }

    @Test("a non-@ObservableState State captures no fields (legacy gate)")
    func nonObservableStateGates() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Form {
            struct State: Equatable { var text = "" }
            enum Action: BindableAction { case binding(BindingAction<State>) }
            var body: some Reducer<State, Action> { BindingReducer(); Reduce { _, _ in .none } }
        }
        """
        #expect(ReducerDiscoverer.discover(source: source, file: "Form.swift")[0].stateFields.isEmpty)
    }
}
