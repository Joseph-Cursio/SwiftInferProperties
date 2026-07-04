// Curated from Point-Free's swift-composable-architecture examples
// (01-GettingStarted-Counter.swift) for the Tier-2 measured corpus. The SwiftUI
// View / #Preview scaffolding is stripped; the `@Reducer` is kept verbatim so
// determinism measured-verify can compile it against ComposableArchitecture in a
// flat module. Original: MIT-licensed, Copyright (c) 2020 Point-Free, Inc. See
// ATTRIBUTION.md.
import ComposableArchitecture

@Reducer
struct Counter {
  @ObservableState
  struct State: Equatable {
    var count = 0
  }

  enum Action {
    case decrementButtonTapped
    case incrementButtonTapped
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .decrementButtonTapped:
        state.count -= 1
        return .none
      case .incrementButtonTapped:
        state.count += 1
        return .none
      }
    }
  }
}
