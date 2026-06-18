// PROTOTYPE — verify-ready SwiftUI MVVM corpus for ViewModel idempotence
// verification. Self-contained (Combine only, no app frameworks) so the
// verifier can co-compile + construct each model. Mirrors the per-family
// verify corpora (a true positive + a deliberate false positive), plus a
// dependency-requiring model that the constructibility gate must SKIP.

import Combine

final class SelectionModel: ObservableObject {
    @Published var selectedIDs: Set<Int> = []
    @Published var items: [Int] = [1, 2, 3]
    @Published var cursor: Int = 0

    /// Idempotent — selecting all twice == once → measured-bothPass.
    func selectAll() {
        selectedIDs = Set(items)
    }

    /// Idempotent — reset twice == once → measured-bothPass.
    func reset() {
        selectedIDs.removeAll()
        cursor = 0
    }

    /// NOT idempotent — advances the cursor, so applying twice differs
    /// from once. The name matches the `select*` idempotence vocabulary,
    /// so it surfaces as a candidate and only execution disproves it →
    /// the deliberate false positive (measured-defaultFails).
    func selectNext() {
        cursor = min(cursor + 1, items.count - 1)
    }
}

final class ConfiguredModel: ObservableObject {
    @Published var ready: Bool = false
    /// An injected dependency with no default — makes `ConfiguredModel()`
    /// impossible, so the constructibility gate marks this view model
    /// `.requiresArguments(["endpoint"])` and verify SKIPS it (the MVVM
    /// analog of the refint Identifiable gate). `reset` would otherwise
    /// be an idempotence candidate.
    let endpoint: String

    init(endpoint: String) {
        self.endpoint = endpoint
    }

    func reset() {
        ready = false
    }
}
