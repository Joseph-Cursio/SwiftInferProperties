// INTERNAL identity-stability candidates (slice 6e) — Hashable classes.

// POSITIVE control — identity keyed on an immutable field; mutation touches
// only non-identity state, so the hash / == stay stable.
final class PackageStableId: Hashable, @unchecked Sendable {
    let id: Int
    var label: String = ""
    init() { id = 0 }
    static func == (lhs: PackageStableId, rhs: PackageStableId) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    func relabel() { label = "x" }
}

// NEGATIVE control — == / hash read a mutable field a mutation changes, so an
// instance is unsafe as a Set / Dictionary key.
final class PackageMutableKey: Hashable, @unchecked Sendable {
    var name: String = "init"
    init() {}
    static func == (lhs: PackageMutableKey, rhs: PackageMutableKey) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    func rename() { name = "changed" }
}
