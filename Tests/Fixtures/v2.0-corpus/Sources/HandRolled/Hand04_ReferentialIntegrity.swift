// V1.90 hand-rolled v2.0 calibration corpus — fixture 04.
//
// **Family**: Referential Integrity (PRD §5.5).
// **Witness**: Optional whose name lowercases-to-start-with `selected`
// paired with any array `[T]` in the same State, **filtered by
// element-type compatibility** (V1.104 cycle-101a Finding C fix).
// **Carrier**: generic.
//
// Expected witnesses: 1 (selectedMessageID × messages). The
// `drafts: [Draft]` collection is *not* paired because the implied
// element type from `selectedMessageID` is `Message`, not `Draft`.
//
// Pre-v1.104 this fixture used `drafts: [Message]` (same element
// type) which fired 2 Cartesian witnesses. The cycle-101a fixture
// update introduces a distinct `Draft` element type so the filter
// has a real test target — `selectedMessageID` × `drafts: [Draft]`
// is suppressed at detection time rather than surfacing as a
// triage `.rejected` decision.

import struct Foundation.UUID

struct MessageListReducer {
    struct State {
        var selectedMessageID: Message.ID?
        var messages: [Message]
        var drafts: [Draft]
    }
    enum Action {
        case select(Message.ID?)
        case deleteSelected
    }
    static func reduce(_ state: State, _ action: Action) -> State {
        var next = state
        switch action {
        case .select(let id):
            next.selectedMessageID = id
        case .deleteSelected:
            if let id = next.selectedMessageID {
                next.messages.removeAll { $0.id == id }
                next.selectedMessageID = nil
            }
        }
        return next
    }
}

struct Message: Identifiable {
    let id: UUID
    let body: String
}

struct Draft: Identifiable {
    let id: UUID
    let body: String
}
