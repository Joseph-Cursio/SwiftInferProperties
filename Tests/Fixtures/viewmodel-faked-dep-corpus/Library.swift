// PROTOTYPE — verify-ready corpus for DEPENDENCY-FAKING construction. The
// view model injects a `Store` protocol (Void-method requirements), so it
// is NOT zero-arg constructible — the verifier synthesizes a no-op
// `Fake_Store` and constructs `LibraryModel(store: Fake_Store())`, then
// verifies idempotence as usual. Self-contained (Combine).

import Combine

// A richer protocol — a property requirement + non-Void methods + an
// Optional return — all stubbed by the synthesized fake.
protocol Store {
    var name: String { get }
    func save(_ id: Int) async throws
    func clearAll()
    func count() -> Int
    func latest() -> Int?
}

final class LibraryModel: ObservableObject {
    @Published var selected: Set<Int> = []
    @Published var items: [Int] = [1, 2, 3]
    @Published var cursor: Int = 0
    let store: Store

    init(store: Store) {
        self.store = store
    }

    /// Idempotent → bothPass (constructed via the synthesized fake).
    func selectAll() {
        selected = Set(items)
    }

    func deselectAll() {
        selected.removeAll()
    }

    /// NOT idempotent — advances the cursor; the `select*` vocab surfaces
    /// it and execution disproves it → defaultFails.
    func selectNext() {
        cursor = min(cursor + 1, items.count - 1)
    }
}
