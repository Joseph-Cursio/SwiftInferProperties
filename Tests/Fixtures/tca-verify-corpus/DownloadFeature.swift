import ComposableArchitecture
import Foundation

// C2 widening (cycle 130) — real `@Reducer`, MIXED Action with TWO distinct
// non-derivable cases, so the Phase B disclosure lists a richer excluded set
// ("excluded: received, markItems"). `dismiss` is a payload-free idempotent
// witness; `updateStep(Int)` is a raw-payload exploration case (assigned,
// not accumulated — overflow-safe per the cycle-128 finding).
@Reducer
struct DownloadFeature {
    @ObservableState
    struct State: Equatable {
        var presented = false
        var step = 0
        var blob: Data?
        var marked = IndexSet()
    }

    enum Action {
        case start              // driver — presented = true
        case dismiss            // idempotent witness — presented = false
        case updateStep(Int)    // raw payload — exploration only (assigned)
        case received(Data)     // non-derivable — excluded
        case markItems(IndexSet) // non-derivable — excluded
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .start:
                state.presented = true
                return .none
            case .dismiss:
                state.presented = false
                return .none
            case let .updateStep(value):
                state.step = value
                return .none
            case let .received(data):
                state.blob = data
                return .none
            case let .markItems(set):
                state.marked = set
                return .none
            }
        }
    }
}
