import ComposableArchitecture
import Foundation

// C2 (cycle 127) — a verify-ready REAL TCA reducer with a MIXED Action,
// exercising Phase B relaxed partial-exploration: a payload-free idempotent
// witness (`close`), a deliberate `set*` FALSE POSITIVE (`setBadge` reads
// "set to a value" but increments — execution disproves it), a raw-payload
// exploration case (`typed(String)`), and a NON-derivable case
// (`received(Data)`) the generator skips + discloses as excluded.
@Reducer
struct EditorFeature {
    @ObservableState
    struct State: Equatable {
        var isEditing = false
        var title = ""
        var badge = 0
        var payload: Data?
    }

    enum Action {
        case beginEditing      // driver — isEditing = true
        case close             // idempotent witness — isEditing = false
        case setBadge          // set* witness, FALSE POSITIVE — increments
        case typed(String)     // raw payload — exploration only (not a witness)
        case received(Data)    // non-derivable — excluded from exploration
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .beginEditing:
                state.isEditing = true
                return .none
            case .close:
                state.isEditing = false
                return .none
            case .setBadge:
                state.badge += 1
                return .none
            case let .typed(text):
                state.title = text
                return .none
            case let .received(data):
                state.payload = data
                return .none
            }
        }
    }
}
