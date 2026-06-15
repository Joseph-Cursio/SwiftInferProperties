import ComposableArchitecture
import Foundation

// Cycle 138 — referential-integrity verify corpus, fixture 1 of 2: the
// valid reducer (the un-gated `bothPass → .verified` proof).
//
// State pairs a `selected*` Optional ID (`selectedBookID`) with a
// collection (`books: [Book]`) → a ReferentialIntegrityWitness
// (`state.selectedBookID == nil || state.books.contains { $0.id ==
// state.selectedBookID }`). `Book` is `Identifiable`, so the `$0.id`
// predicate compiles directly. The reducer keeps the selection valid:
// `choose` only ever points at an existing book (or nil), and `wipe`
// clears both — so the invariant holds at `State()` and after every action
// → a `measured-bothPass`.
//
// Referential integrity is UN-GATED (no swiftProjectLintDeferral), so the
// bothPass promotes through the normal path (30 + 50 = 80 → .strong →
// .verified) — no pin-overrule, no disclosure — exactly like conservation.
//
// `selectedBookID` implies element type "Book", which matches `[Book]`
// (cycle-101a element-type filter). Action names avoid the idempotence
// witness vocabulary, so the only family this reducer surfaces is refint.
@Reducer
struct LibraryFeature {
    @ObservableState
    struct State: Equatable {
        var selectedBookID: Int?
        var books: [Book] = []
    }

    enum Action {
        case add
        case choose
        case wipe
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .add:
                state.books.append(Book(id: state.books.count, title: "Book"))
                return .none
            case .choose:
                // Always points at an existing book (or nil if empty).
                state.selectedBookID = state.books.last?.id
                return .none
            case .wipe:
                state.books.removeAll()
                state.selectedBookID = nil
                return .none
            }
        }
    }
}

struct Book: Equatable, Identifiable {
    let id: Int
    var title: String
}
