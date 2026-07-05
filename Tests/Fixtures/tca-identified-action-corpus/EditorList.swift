// Item 2 slice 3c — a `.forEach` parent over `Editor`, whose child action is
// NOT payload-free. `IdentifiedActionResolver` resolves
// `editors(IdentifiedActionOf<Editor>)` by picking Editor's raw `setText(String)`
// case (3c), constructing `.element(id: <canned UUID>, action:
// Editor.Action.setText(""))`. Both branches are deterministic, so determinism
// verifies `bothPass` — proving 3c builds a payload-bearing child action that
// compiles against CA. (Like RowList, the `.element` no-ops against empty
// `editors`.)
import ComposableArchitecture

@Reducer
struct EditorList {
    @ObservableState
    struct State: Equatable {
        var editors: IdentifiedArrayOf<Editor.State> = []
        var isLocked = false
    }

    enum Action {
        case lockToggled
        case editors(IdentifiedActionOf<Editor>)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .lockToggled:
                state.isLocked.toggle()
                return .none
            case .editors:
                return .none
            }
        }
        .forEach(\.editors, action: \.editors) {
            Editor()
        }
    }
}
