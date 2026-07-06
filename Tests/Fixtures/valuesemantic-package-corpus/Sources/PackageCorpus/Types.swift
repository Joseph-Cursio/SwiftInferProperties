// INTERNAL (no `public`) value-semantics candidates — reachable only via
// `@testable import` (slice 5b). Stored members are annotated so the discoverer
// classifies them (the engine's textual-type posture).

// NEGATIVE control — shares a reference across value copies (leaks).
struct PackageLeaky: Equatable {
    final class Box: @unchecked Sendable { var value: Int = 0 }
    var box: Box = Box()
    init() {}
    static func == (lhs: PackageLeaky, rhs: PackageLeaky) -> Bool { lhs.box.value == rhs.box.value }
    // Not `mutating`: mutates through the shared reference (the Example-1 shape).
    func bump() { box.value += 1 }
}

// POSITIVE control — correct copy-on-write (clones shared storage on mutation).
struct PackageSafe: Equatable {
    final class Storage: @unchecked Sendable {
        var items: [Int]
        init(_ items: [Int] = []) { self.items = items }
        func clone() -> Storage { Storage(items) }
    }
    var storage: Storage = Storage()
    init() {}
    static func == (lhs: PackageSafe, rhs: PackageSafe) -> Bool { lhs.storage.items == rhs.storage.items }
    mutating func addOne() {
        if !isKnownUniquelyReferenced(&storage) { storage = storage.clone() }
        storage.items.append(1)
    }
}
