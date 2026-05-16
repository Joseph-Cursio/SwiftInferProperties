// V1.90 hand-rolled v2.0 calibration corpus — fixture 04.
//
// **Family**: Referential Integrity (PRD §5.5).
// **Witness**: Optional whose name lowercases-to-start-with `selected`
// Cartesian-paired with any array `[T]` in the same State.
// **Carrier**: generic.
//
// Expected witnesses: 2 (selectedMessageID × messages,
// selectedMessageID × drafts). Both arrays pair with the single
// selected Optional because the detector takes the Cartesian product.

import struct Foundation.UUID

struct MessageListReducer {
    struct State {
        var selectedMessageID: Message.ID?
        var messages: [Message]
        var drafts: [Message]
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
