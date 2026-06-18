// PROTOTYPE — verify-ready corpus for KEYED referential integrity: a
// scalar-key selection (`selectedTrackID: Int?`) references a collection
// of `Identifiable` elements (`[Track]`) by `\.id`. This is the common
// real-world shape (e.g. `ViolationInspectorViewModel.selectedViolationId`
// over `[Violation]`), gated by the Identifiable classifier. Self-contained.

import Combine

struct Track: Identifiable {
    let id: Int
    let title: String
}

final class SafePlaylistModel: ObservableObject {
    @Published var tracks: [Track] = [Track(id: 1, title: "a"), Track(id: 2, title: "b")]
    @Published var selectedTrackID: Int?

    /// Selects an existing track's id → keyed refint maintained → bothPass.
    func selectFirst() {
        selectedTrackID = tracks.first?.id
    }

    func deselect() {
        selectedTrackID = nil
    }
}

final class GhostPlaylistModel: ObservableObject {
    @Published var tracks: [Track] = [Track(id: 1, title: "a"), Track(id: 2, title: "b")]
    @Published var selectedTrackID: Int?

    func selectFirst() {
        selectedTrackID = tracks.first?.id
    }

    /// Selects an id no track has → `selectedTrackID` dangles → the keyed
    /// invariant `tracks.contains { $0.id == selectedTrackID! }` fails →
    /// defaultFails.
    func selectGhost() {
        selectedTrackID = 999
    }
}
