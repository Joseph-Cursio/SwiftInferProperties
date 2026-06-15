import ComposableArchitecture
import Foundation

// Cycle 143 — referential-integrity verify corpus widening, fixture 5 of 5:
// a false positive with a DIFFERENT bug shape than CatalogFeature.
//
// CatalogFeature drifts by REMOVING the selected item (remove-dangling).
// GalleryFeature drifts the other way — `.pickGhost` directly sets
// `selectedPhotoID` to an id that never exists in `photos` (ids are
// 0..<count), so the selection points at a phantom from the moment it's
// set. After `.pickGhost`: `selectedPhotoID = 999` with no matching photo →
// the per-step precondition `state.selectedPhotoID == nil ||
// state.photos.contains { $0.id == state.selectedPhotoID }` traps →
// `measured-defaultFails` → suppressed. Only execution disproves it.
@Reducer
struct GalleryFeature {
    @ObservableState
    struct State: Equatable {
        var selectedPhotoID: Int?
        var photos: [Photo] = []
    }

    enum Action {
        case add
        case pickGhost
        case wipe
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .add:
                state.photos.append(Photo(id: state.photos.count))
                return .none
            case .pickGhost:
                // BUG (deliberate): selects an id that never exists (photo ids
                // are 0..<count), so the selection dangles immediately.
                state.selectedPhotoID = 999
                return .none
            case .wipe:
                state.photos.removeAll()
                state.selectedPhotoID = nil
                return .none
            }
        }
    }
}

struct Photo: Equatable, Identifiable {
    let id: Int
}
