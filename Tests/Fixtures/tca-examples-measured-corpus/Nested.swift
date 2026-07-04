// Curated from Point-Free's swift-composable-architecture examples
// (05-HigherOrderReducers-Recursion.swift) for the Tier-2 measured corpus. The
// SwiftUI View / #Preview scaffolding is stripped; the `@Reducer` is kept
// verbatim. A recursive reducer (`.forEach` over `Self()`) with one pinned CA
// built-in dependency (`\.uuid`). Original: MIT-licensed, Copyright (c) 2020
// Point-Free, Inc. See ATTRIBUTION.md.
import ComposableArchitecture
import Foundation

@Reducer
struct Nested {
  @ObservableState
  struct State: Equatable, Identifiable {
    let id: UUID
    var name: String = ""
    var rows: IdentifiedArrayOf<State> = []

    init(id: UUID? = nil, name: String = "", rows: IdentifiedArrayOf<State> = []) {
      @Dependency(\.uuid) var uuid
      self.id = id ?? uuid()
      self.name = name
      self.rows = rows
    }
  }

  enum Action {
    case addRowButtonTapped
    case nameTextFieldChanged(String)
    case onDelete(IndexSet)
    indirect case rows(IdentifiedActionOf<Nested>)
  }

  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .addRowButtonTapped:
        state.rows.append(State(id: self.uuid()))
        return .none
      case .nameTextFieldChanged(let name):
        state.name = name
        return .none
      case .onDelete(let indexSet):
        state.rows.remove(atOffsets: indexSet)
        return .none
      case .rows:
        return .none
      }
    }
    .forEach(\.rows, action: \.rows) {
      Self()
    }
  }
}
