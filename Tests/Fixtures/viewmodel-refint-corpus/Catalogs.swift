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

/// An ORDER-DEPENDENT refint bug: the invariant holds when the actions are
/// applied once in sorted order (`drop` then `pick` — alphabetical), so the old
/// single-deterministic-pass verifier PASSED it; but `pick` then `drop` violates
/// `selected ⊆ items`, which only randomized multi-step sequences reach →
/// measured-defaultFails. The proof that sequence exploration finds interleaving
/// bugs a single pass misses.
final class OrderBugModel: ObservableObject {
    @Published var items: [Int] = [1, 2, 3]
    @Published var selected: Set<Int> = []

    /// Selects the first CURRENTLY-PRESENT item — safe in isolation (nothing to
    /// select once `items` is empty).
    func pick() {
        if let first = items.first {
            selected.insert(first)
        }
    }

    /// Clears `items` but NOT `selected` — so a prior `pick` is left dangling.
    func drop() {
        items = []
    }
}
