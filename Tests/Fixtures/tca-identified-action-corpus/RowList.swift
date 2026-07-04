// Item 2 slice 3 — the parent of an `IdentifiedActionOf<Child>` composition:
// a `.forEach(\.rows, action: \.rows) { Row() }` reducer whose Action carries
// `case rows(IdentifiedActionOf<Row>)`. This is the shape the slice targets.
//
// Two action cases: `editToggled` (payload-free — makes the parent constructible
// even *before* slice 3, so the slice's effect is visible as `rows` moving from
// excluded → explored) and `rows(IdentifiedActionOf<Row>)` (the composition case
// `IdentifiedActionResolver` resolves into `.element(id: <canned UUID>, action:
// .increment)`). Both branches are deterministic — no `UUID()` / clock in the
// body — so the determinism family verifies `bothPass`. The constructed
// `.element` **no-ops against the empty initial `rows`** (`.forEach` finds no
// element with the canned id), so this widens the explored action space without
// new counterexample signal, exactly as the slice-3 design's ROI reframe states.
import ComposableArchitecture

@Reducer
struct RowList {
    @ObservableState
    struct State: Equatable {
        var rows: IdentifiedArrayOf<Row.State> = []
        var isEditing = false
    }

    enum Action {
        case editToggled
        case rows(IdentifiedActionOf<Row>)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .editToggled:
                state.isEditing.toggle()
                return .none
            case .rows:
                return .none
            }
        }
        .forEach(\.rows, action: \.rows) {
            Row()
        }
    }
}
