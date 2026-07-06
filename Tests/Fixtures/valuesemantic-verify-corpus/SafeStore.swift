// Verify-ready value-semantics corpus — POSITIVE control (correct copy-on-write).
//
// `SafeStore` wraps a reference-typed `Storage`, but its `mutating` method
// clones the storage when it isn't uniquely referenced, so a mutation applied
// to a copy never touches the original. The copy-mutate-compare law must PASS
// (`measured-bothPass`) — this is the guard against false positives on a
// legitimately value-semantic CoW container.

public struct SafeStore: Equatable, Sendable {

    final class Storage: @unchecked Sendable {
        var items: [Int]
        init(_ items: [Int] = []) { self.items = items }
        func clone() -> Storage { Storage(items) }
    }

    private var storage: Storage = Storage()

    public init() {}

    public var items: [Int] { storage.items }

    public static func == (lhs: SafeStore, rhs: SafeStore) -> Bool {
        lhs.storage.items == rhs.storage.items
    }

    public mutating func addOne() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.clone()
        }
        storage.items.append(1)
    }
}
