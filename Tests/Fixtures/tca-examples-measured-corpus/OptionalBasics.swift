// Curated from Point-Free's swift-composable-architecture examples
// (01-GettingStarted-OptionalState.swift) for the Tier-2 measured corpus. The
// SwiftUI View / #Preview scaffolding is stripped; the `@Reducer` is kept
// verbatim. It composes `Counter` via `.ifLet`, so `Counter.swift` must live in
// the same module. Original: MIT-licensed, Copyright (c) 2020 Point-Free, Inc.
// See ATTRIBUTION.md.
import ComposableArchitecture

@Reducer
struct OptionalBasics {
  @ObservableState
  struct State: Equatable {
    var optionalCounter: Counter.State?
  }

  enum Action {
    case optionalCounter(Counter.Action)
    case toggleCounterButtonTapped
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .toggleCounterButtonTapped:
        state.optionalCounter =
          state.optionalCounter == nil
          ? Counter.State()
          : nil
        return .none
      case .optionalCounter:
        return .none
      }
    }
    .ifLet(\.optionalCounter, action: \.optionalCounter) {
      Counter()
    }
  }
}
