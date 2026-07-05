// Item 2 slice 3c — a child whose Action has NO payload-free case (only a
// raw-payload `setText(String)`). 3b (payload-free base case) can't construct a
// child action for it; slice 3c picks the raw case and builds
// `Editor.Action.setText("")` via the shared defaultValueLiteral. `id` is a
// fixed-default UUID so Editor's own State is zero-arg constructible +
// deterministic (see Row.swift). `import Foundation` for `UUID`.
import ComposableArchitecture
import Foundation

@Reducer
struct Editor {
    @ObservableState
    struct State: Equatable, Identifiable {
        var id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        var text = ""
    }

    enum Action {
        case setText(String)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setText(value):
                state.text = value
                return .none
            }
        }
    }
}
