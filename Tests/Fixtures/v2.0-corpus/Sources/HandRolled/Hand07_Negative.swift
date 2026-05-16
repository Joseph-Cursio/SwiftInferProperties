// V1.90 hand-rolled v2.0 calibration corpus — fixture 07.
//
// **Purpose**: confirm the detectors are conservative — this
// reducer + the non-reducer helpers below should produce zero
// interaction-invariant witnesses across all 5 families. If any
// fire on this fixture, that's a false positive worth filing.
//
// **Reducer present**: yes (`PlainReducer.update`). State has
// fields that look superficially state-shaped but match no curated
// pattern: `total` (not "count*"), `entries` (paired with `total`
// but `total` doesn't lower-contain "count" so Conservation
// shouldn't fire), no `Showing`/`Presenting` Bools, no Optional
// with `selected` prefix, no Bool from the biconditional curated
// list.
//
// **Non-reducer present**: yes (`utility`, `transform`) — should
// be ignored by ReducerDiscoverer's signature filter.

struct PlainReducer {
    struct State {
        var total: Int
        var entries: [String]
    }
    enum Action {
        case add(String)
        case remove(String)
    }
    static func update(_ state: State, _ action: Action) -> State {
        var next = state
        switch action {
        case .add(let value):
            next.entries.append(value)
            next.total += 1
        case .remove(let value):
            if let index = next.entries.firstIndex(of: value) {
                next.entries.remove(at: index)
                next.total -= 1
            }
        }
        return next
    }
}

// MARK: - Non-reducer helpers (must be ignored by signature scan)

func utility(_ value: String) -> Int {
    value.count
}

func transform(_ lhs: Int, _ rhs: Int) -> Int {
    lhs + rhs
}
