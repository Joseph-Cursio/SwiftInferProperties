// V1.90 hand-rolled v2.0 calibration corpus — fixture 03.
//
// **Family**: Cardinality (PRD §5.4).
// **Witness**: ≥ 2 Bool fields containing `Showing`/`Presenting`
// (case-sensitive) OR Optional fields whose lowercased name
// contains `sheet`/`alert`/`fullscreencover`/`popover`.
// **Carrier**: generic.
//
// Expected witnesses: 1 (the State has 3 cardinality-matched fields:
// isShowingSheet + isShowingAlert + activeFullScreenCover — the
// detector emits one combined witness covering at-most-one-of).

struct PresentationReducer {
    struct State {
        var isShowingSheet: Bool
        var isShowingAlert: Bool
        var activeFullScreenCover: String?
        var unrelatedString: String
    }
    enum Action {
        case showSheet
        case showAlert
        case showCover(String)
        case dismissAll
    }
    static func reduce(_ state: State, _ action: Action) -> State {
        var next = state
        switch action {
        case .showSheet: next.isShowingSheet = true
        case .showAlert: next.isShowingAlert = true
        case .showCover(let title): next.activeFullScreenCover = title
        case .dismissAll:
            next.isShowingSheet = false
            next.isShowingAlert = false
            next.activeFullScreenCover = nil
        }
        return next
    }
}
