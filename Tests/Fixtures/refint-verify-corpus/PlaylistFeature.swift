import ComposableArchitecture
import Foundation

// Cycle 143 — referential-integrity verify corpus widening, fixture 4 of 5:
// the IdentifiedArrayOf collection shape.
//
// The original trio (Library/Catalog/Note) pairs a `selected*` Optional ID
// with a plain `[T]` array. This reducer uses TCA's idiomatic
// `IdentifiedArrayOf<Track>` collection instead — the detector recognizes it
// (element type `Track`) and the emitted `state.tracks.contains { $0.id ==
// state.selectedTrackID }` predicate compiles against it (IdentifiedArray is
// a RandomAccessCollection of Identifiable elements). The reducer keeps the
// selection valid (`pick` only ever points at an existing track or nil), so
// the invariant holds at `State()` and after every action →
// `measured-bothPass` → un-gated promotion `.possible → .verified`.
@Reducer
struct PlaylistFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTrackID: Int?
        var tracks: IdentifiedArrayOf<Track> = []
    }

    enum Action {
        case add
        case pick
        case clearList
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .add:
                state.tracks.append(Track(id: state.tracks.count, title: "Track"))
                return .none
            case .pick:
                state.selectedTrackID = state.tracks.last?.id
                return .none
            case .clearList:
                state.tracks.removeAll()
                state.selectedTrackID = nil
                return .none
            }
        }
    }
}

struct Track: Equatable, Identifiable {
    let id: Int
    var title: String
}
