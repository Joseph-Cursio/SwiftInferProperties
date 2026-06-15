import ComposableArchitecture
import Foundation

// C2 widening (cycle 128) — real `@Reducer`, MIXED Action (Phase B). The
// point: `setEnabled` is a `set*` witness that is a genuine TRUE positive
// (sets a flag to a fixed value → idempotent), the mirror image of
// `EditorFeature.setBadge` (a `set*` FALSE positive). Execution distinguishes
// them — the campaign's precision story in both directions. Also exercises
// the exact witness `cancel`, a raw-payload exploration case (`adjust(Int)`,
// non-witness), and a non-derivable excluded case (`sync(Data)`).
@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var enabled = false
        var cancelled = false
        var volume = 0
        var blob: Data?
    }

    enum Action {
        case toggle          // driver — flips enabled
        case setEnabled      // set* witness — TRUE positive (enabled = true)
        case cancel          // exact witness — cancelled = true
        case adjust(Int)     // raw payload — exploration only (not a witness)
        case sync(Data)      // non-derivable — excluded from exploration
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .toggle:
                state.enabled.toggle()
                return .none
            case .setEnabled:
                state.enabled = true
                return .none
            case .cancel:
                state.cancelled = true
                return .none
            case let .adjust(value):
                // Assign (not `+=`) so a full-range generated Int can't
                // overflow-trap during exploration — that would fail every
                // witness on this reducer, not the behavior we're curating.
                state.volume = value
                return .none
            case let .sync(data):
                state.blob = data
                return .none
            }
        }
    }
}
