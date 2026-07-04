// Open-alphabet redux corpus for the `unknownActionIsNoOp` measured family.
//
// Both reducers dispatch over an OPEN Action alphabet — a marker protocol
// `AppAction`, not a closed enum — so discovery records `actionCases` empty and
// the family fires (a closed enum is exhaustive, so "unknown" is unrepresentable
// and the family is skipped as vacuous). No ComposableArchitecture dependency:
// this is plain-Swift protocol dispatch, so the measured build is fast.
//
// The probe the verifier mints (`__UnknownActionProbe: AppAction`) is a fresh
// conforming type neither reducer recognises, so it lands in the `default`
// branch:
//   - `NoOpCounter` leaves State untouched on the default branch → the property
//     `reduce(s, unknown) == s` holds → measured-bothPass → Verified.
//   - `LeakyReducer` MUTATES State on the default branch (bumps `unknownHits`) →
//     the property is falsified → the stub's precondition traps →
//     measured-defaultFails → suppressed. This proves the check has teeth.

/// The open Action alphabet. An empty marker protocol: any type can conform,
/// so the reducer can never enumerate every possible action — the premise of
/// the whole family.
public protocol AppAction {}

/// A recognised action. Internal — only the reducers switch on it; the verifier
/// never needs it (it mints its own probe).
struct Increment: AppAction {}

// MARK: - Passes: default branch is a genuine no-op

public struct NoOpCounter {
    public struct State: Equatable, Sendable {
        public var count: Int
        public init(count: Int = 0) {
            self.count = count
        }
    }

    public static func reduce(_ state: State, _ action: AppAction) -> State {
        switch action {
        case is Increment:
            return State(count: state.count + 1)
        default:
            // Unrecognised action → leave State exactly as-is.
            return state
        }
    }
}

// MARK: - Fails: default branch mutates State (the anti-pattern this catches)

public struct LeakyReducer {
    public struct State: Equatable, Sendable {
        public var count: Int
        public var unknownHits: Int
        public init(count: Int = 0, unknownHits: Int = 0) {
            self.count = count
            self.unknownHits = unknownHits
        }
    }

    public static func reduce(_ state: State, _ action: AppAction) -> State {
        switch action {
        case is Increment:
            return State(count: state.count + 1, unknownHits: state.unknownHits)
        default:
            // BUG: an unrecognised action must be a no-op, but this bumps a
            // counter — so `reduce(s, unknown) != s`.
            return State(count: state.count, unknownHits: state.unknownHits + 1)
        }
    }
}
