// Curated from Point-Free's swift-composable-architecture examples
// (01-GettingStarted-Bindings-Basics.swift) for the Tier-2 measured corpus. The
// SwiftUI View / #Preview scaffolding is stripped; the `@Reducer` is kept
// verbatim. Pure (no dependencies). Original: MIT-licensed, Copyright (c) 2020
// Point-Free, Inc. See ATTRIBUTION.md.
import ComposableArchitecture

@Reducer
struct BindingBasics {
  @ObservableState
  struct State: Equatable {
    var sliderValue = 5.0
    var stepCount = 10
    var text = ""
    var toggleIsOn = false
  }

  enum Action {
    case sliderValueChanged(Double)
    case stepCountChanged(Int)
    case textChanged(String)
    case toggleChanged(isOn: Bool)
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .sliderValueChanged(let value):
        state.sliderValue = value
        return .none
      case .stepCountChanged(let count):
        state.sliderValue = .minimum(state.sliderValue, Double(count))
        state.stepCount = count
        return .none
      case .textChanged(let text):
        state.text = text
        return .none
      case .toggleChanged(let isOn):
        state.toggleIsOn = isOn
        return .none
      }
    }
  }
}
