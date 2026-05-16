// V1.90 hand-rolled v2.0 calibration corpus — fixture 05.
//
// **Family**: Biconditional / iff (PRD §5.6).
// **Witness**: Bool field whose name contains
// Loading/Showing/Presenting/Active/Fetching/Refreshing
// Cartesian-paired with any Optional field in the same State.
// **Carrier**: generic.
//
// Expected witnesses: 2 (isLoadingResults × activeTask,
// isLoadingResults × cachedResult). The detector pairs the one
// Bool against every Optional in the same State.

struct FetchReducer {
    struct State {
        var isLoadingResults: Bool
        var activeTask: TaskHandle?
        var cachedResult: String?
        var unrelatedCount: Int
    }
    enum Action {
        case startFetch
        case fetchCompleted(String)
        case fetchCancelled
    }
    static func reduce(_ state: State, _ action: Action) -> State {
        var next = state
        switch action {
        case .startFetch:
            next.isLoadingResults = true
        case .fetchCompleted(let value):
            next.isLoadingResults = false
            next.activeTask = nil
            next.cachedResult = value
        case .fetchCancelled:
            next.isLoadingResults = false
            next.activeTask = nil
        }
        return next
    }
}

struct TaskHandle {
    let identifier: String
}
