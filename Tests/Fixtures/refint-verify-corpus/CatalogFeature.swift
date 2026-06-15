import ComposableArchitecture
import Foundation

// Cycle 138 — referential-integrity verify corpus, fixture 2 of 2: the
// FALSE POSITIVE (the refint analogue of the conservation corpus's
// setBadge / the cardinality corpus's LeakyFeature).
//
// State pairs a `selected*` Optional ID (`selectedItemID`) with a
// collection (`items: [Item]`) → a ReferentialIntegrityWitness fires
// statically: a selection pointing at a removed item is *representable*, so
// the detector emits the suggestion. But the reducer drifts the pair out of
// integrity — `.removeFirst` drops an item WITHOUT clearing/updating the
// selection. The sequence [add, choose, removeFirst] leaves
// `selectedItemID` pointing at an item that no longer exists, so the
// per-step precondition traps → `measured-defaultFails` → suppressed. Only
// execution disproves the static smell.
//
// All cases are payload-free (full coverage), so this is a clean
// defaultFails.
@Reducer
struct CatalogFeature {
    @ObservableState
    struct State: Equatable {
        var selectedItemID: Int?
        var items: [Item] = []
    }

    enum Action {
        case add
        case choose
        case removeFirst
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .add:
                state.items.append(Item(id: state.items.count, name: "Item"))
                return .none
            case .choose:
                state.selectedItemID = state.items.first?.id
                return .none
            case .removeFirst:
                // BUG (deliberate): removes an item but leaves the selection
                // dangling — a stale `selectedItemID` survives the removal.
                if !state.items.isEmpty { state.items.removeFirst() }
                return .none
            }
        }
    }
}

struct Item: Equatable, Identifiable {
    let id: Int
    var name: String
}
