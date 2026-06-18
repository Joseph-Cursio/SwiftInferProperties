// PROTOTYPE — verify-ready corpus for ViewModel referential-integrity
// verification. The invariant: the `selected` set always references
// elements of `items` (a value-membership refint, the verifiable shape —
// selection element type == collection element type). Self-contained
// (Combine only) so the verifier can construct + drive each model.

import Combine

final class SafeCatalogModel: ObservableObject {
    @Published var items: [Int] = [1, 2, 3]
    @Published var selected: Set<Int> = []

    func selectAll() {
        selected = Set(items)
    }

    func deselectAll() {
        selected.removeAll()
    }

    /// Guards membership before inserting — so `selected ⊆ items` is
    /// maintained by every action → measured-bothPass.
    func selectIfPresent(_ id: Int) {
        if items.contains(id) {
            selected.insert(id)
        }
    }
}

final class CatalogModel: ObservableObject {
    @Published var items: [Int] = [1, 2, 3]
    @Published var selected: Set<Int> = []

    func selectAll() {
        selected = Set(items)
    }

    func deselectAll() {
        selected.removeAll()
    }

    /// BREAKS refint — inserts an arbitrary id without checking it's an
    /// item, so driving `toggle(0)` (0 ∉ items) drives `selected` out of
    /// `items` → measured-defaultFails.
    func toggle(_ id: Int) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }
}
