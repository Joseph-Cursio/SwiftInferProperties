// Curated from Point-Free's swift-composable-architecture examples
// (03-Effects-Timers.swift) for the Tier-2 measured corpus. The SwiftUI View /
// #Preview scaffolding is stripped; the `@Reducer` is kept verbatim. It declares
// a single CA built-in dependency (`\.continuousClock`), which the verifier pins
// to a constant — so its determinism check should measure bothPass (a declared,
// pinned dependency is fine). Original: MIT-licensed, Copyright (c) 2020
// Point-Free, Inc. See ATTRIBUTION.md.
import ComposableArchitecture

@Reducer
struct Timers {
  @ObservableState
  struct State: Equatable {
    var isTimerActive = false
    var secondsElapsed = 0
  }

  enum Action {
    case onDisappear
    case timerTicked
    case toggleTimerButtonTapped
  }

  @Dependency(\.continuousClock) var clock
  private enum CancelID { case timer }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .onDisappear:
        return .cancel(id: CancelID.timer)

      case .timerTicked:
        state.secondsElapsed += 1
        return .none

      case .toggleTimerButtonTapped:
        state.isTimerActive.toggle()
        return .run { [isTimerActive = state.isTimerActive] send in
          guard isTimerActive else { return }
          for await _ in self.clock.timer(interval: .seconds(1)) {
            await send(.timerTicked, animation: .interpolatingSpring(stiffness: 3000, damping: 40))
          }
        }
        .cancellable(id: CancelID.timer, cancelInFlight: true)
      }
    }
  }
}
