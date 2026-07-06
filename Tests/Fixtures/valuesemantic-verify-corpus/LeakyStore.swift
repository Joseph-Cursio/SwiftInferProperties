// Verify-ready value-semantics corpus — NEGATIVE control (reference leak).
//
// `LeakyStore` shares its reference-typed `Storage` across value copies: a
// struct copy duplicates the `storage` reference, not the underlying object.
// `addOne` mutates through that shared reference — and is (correctly) NOT
// `mutating`, since it never reassigns `self` (the Example-1 shape, pbt-book
// Ch. 9 §9.1.3). So a mutation applied to a *copy* is observable through the
// original, and the copy-mutate-compare law must FAIL (`measured-defaultFails`).

public struct LeakyStore: Equatable, Sendable {

    final class Storage: @unchecked Sendable {
        var items: [Int]
        init(_ items: [Int] = []) { self.items = items }
    }

    private var storage: Storage = Storage()

    public init() {}

    public var items: [Int] { storage.items }

    public static func == (lhs: LeakyStore, rhs: LeakyStore) -> Bool {
        lhs.storage.items == rhs.storage.items
    }

    // Not `mutating`: it mutates the *referenced* object, not `self` — so the
    // shared storage leaks the copy's append back into the original.
    public func addOne() {
        storage.items.append(1)
    }
}
