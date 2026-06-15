import ComposableArchitecture
import Foundation

// Cycle 144 — tca-verify-corpus widening: new raw payload generators
// (Double + Bool).
//
// The corpus has exercised only Int (`updateStep`/`adjust`) and String
// (`typed`) raw exploration payloads. This reducer adds `tune(Double)` and
// `flag(Bool)` — driving the `Gen<Double>.double(…)` and `Gen<Bool>.bool()`
// generators (RawType) during exploration. Both are constructible, so the
// exploration is FULL coverage (no excluded cases). The payload-free
// `reset` is the idempotence witness: it sets State back to defaults, so
// applying it twice (after any explored sequence) equals once →
// `measured-bothPass`.
@Reducer
struct GaugeFeature {
    @ObservableState
    struct State: Equatable {
        var rate: Double = 0
        var enabled: Bool = false
        var level: Int = 0
    }

    enum Action {
        case reset             // payload-free idempotence witness
        case tune(Double)      // Double raw generator
        case flag(Bool)        // Bool raw generator
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .reset:
                state = State()
                return .none
            case let .tune(value):
                state.rate = value
                return .none
            case let .flag(on):
                state.enabled = on
                return .none
            }
        }
    }
}
