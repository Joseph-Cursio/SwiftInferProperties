// V1.90 hand-rolled v2.0 calibration corpus — fixture 02.
//
// **Family**: Idempotence (PRD §5.3).
// **Witness**: Action case name in the curated exact set
// (refresh / reset / clear / dismiss / cancel / close / hide / select)
// or starting with a curated prefix (set / select / show / present).
// **Carrier**: generic (method on a struct).
//
// Expected witnesses: 4 (refresh, clear, dismiss, setColor).
// `noop` doesn't match either rule.

struct SettingsReducer {
    struct State {
        var color: String
        var theme: String
    }
    enum Action {
        case refresh
        case clear
        case dismiss
        case setColor(String)
        case noop
    }
    static func reduce(_ state: State, _ action: Action) -> State {
        switch action {
        case .refresh, .clear, .dismiss:
            return State(color: "default", theme: "light")
        case .setColor(let color):
            return State(color: color, theme: state.theme)
        case .noop:
            return state
        }
    }
}
