// Item 2 slice 4 — a self-contained modern TCA form reducer (no custom
// DependencyKey, so it co-compiles against CA alone) whose Action carries a
// `case binding(BindingAction<State>)`. The verifier explores
// `Action.binding(.set(\.field, <canned value>))` for each `@ObservableState`
// stored `var` of a defaultable type (String / Bool / Double / Int) — a real
// transition through `BindingReducer`, no `Gen` over the field needed.
//
// The body pairs `BindingReducer()` with a `Reduce { … }` closure: the closure
// is what discovery keys on (a pure `BindingReducer()`-only body surfaces no
// reducer candidate), and it also gives a payload-free `resetTapped` case so the
// reducer is constructible independent of the binding case. Every branch is
// deterministic, so the determinism family verifies `bothPass`.
import ComposableArchitecture

@Reducer
struct Settings {
    @ObservableState
    struct State: Equatable {
        var displayName = ""
        var notificationsEnabled = false
        var fontScale = 1.0
        var retryCount = 0
    }

    enum Action: BindableAction {
        case resetTapped
        case binding(BindingAction<State>)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .resetTapped:
                state.displayName = ""
                state.notificationsEnabled = false
                state.fontScale = 1.0
                state.retryCount = 0
                return .none
            case .binding:
                return .none
            }
        }
    }
}
