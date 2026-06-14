// Cycle 116 — verify-ready idempotence survey corpus, widening fixture.
//
// TCA-convention reducer covering the three canonical TCA Action-name
// witnesses (cycle-93 V1.96 additions): `task` (subscribe to a long-living
// effect — state-level idempotent for the same payload), `delegate` (the
// child reducer no-ops; the parent observes — trivially idempotent), and
// `binding` (a key-path setter — assigning the same value twice = once).
// Modeled payload-free so `Action` is `CaseIterable` (real TCA carries
// associated values; the witness detector matches on name regardless, and
// a payload-free model is what the verify stub can drive). `increment` is
// a non-witness driver.

public struct TCAFeatureReducer {
    public struct State: Equatable, Sendable {
        public var isLoading: Bool
        public var value: Int
        public init(isLoading: Bool = false, value: Int = 0) {
            self.isLoading = isLoading
            self.value = value
        }
    }

    public enum Action: CaseIterable, Sendable {
        case increment
        case task
        case delegate
        case binding
    }

    public static func reduce(_ s: State, _ a: Action) -> State {
        switch a {
        case .increment: return State(isLoading: s.isLoading, value: s.value + 1)
        case .task: return State(isLoading: true, value: s.value)   // subscribe; stays loading
        case .delegate: return s                                     // parent observes; no-op
        case .binding: return State(isLoading: s.isLoading, value: 0) // set to fixed value
        }
    }
}
