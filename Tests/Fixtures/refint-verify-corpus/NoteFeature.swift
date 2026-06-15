import ComposableArchitecture
import Foundation

// Cycle 139 — referential-integrity verify corpus, fixture 3 of 3: the
// NON-IDENTIFIABLE-ELEMENT gate proof.
//
// State pairs a `selected*` Optional ID (`selectedNoteID`) with a
// collection (`notes: [Note]`) → a ReferentialIntegrityWitness fires
// statically (discovery doesn't check Identifiable). But `Note` is NOT
// Identifiable and has no `id` member, so the emitted predicate's `$0.id`
// reference cannot compile. The cycle-139 Identifiable gate detects this
// from the corpus AST and SKIPS the build, surfacing a disclosed
// `architectural-coverage-pending` ("element type `Note` is not
// Identifiable") instead of wasting a doomed `swift build`. The suggestion
// stays `.possible` (the architectural-pending outcome is score-neutral).
@Reducer
struct NoteFeature {
    @ObservableState
    struct State: Equatable {
        var selectedNoteID: Int?
        var notes: [Note] = []
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
                state.notes.append(Note(text: "Note"))
                return .none
            case .choose:
                state.selectedNoteID = state.notes.isEmpty ? nil : 0
                return .none
            case .wipe:
                state.notes.removeAll()
                state.selectedNoteID = nil
                return .none
            }
        }
    }
}

// Deliberately NOT Identifiable and with no `id` member — the gate's target.
struct Note: Equatable {
    var text: String
}
