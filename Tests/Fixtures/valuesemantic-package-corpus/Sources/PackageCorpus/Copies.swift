// INTERNAL defensive-copy candidates (slice 6c) — classes that vend a copy().

// POSITIVE control — deep copy (distinct + independent).
final class PackageCorrectCopy: Equatable, @unchecked Sendable {
    private var items: [Int] = []
    static func == (lhs: PackageCorrectCopy, rhs: PackageCorrectCopy) -> Bool { lhs.items == rhs.items }
    func appendOne() { items.append(1) }
    func copy() -> PackageCorrectCopy {
        let clone = PackageCorrectCopy()
        clone.items = items   // value array → deep-copied
        return clone
    }
}

// NEGATIVE control — a distinct instance that SHARES a mutable reference (shallow).
final class PackageShallowCopy: Equatable, @unchecked Sendable {
    final class Box: @unchecked Sendable { var value: Int = 0 }
    private var box: Box = Box()
    static func == (lhs: PackageShallowCopy, rhs: PackageShallowCopy) -> Bool { lhs.box.value == rhs.box.value }
    func bump() { box.value += 1 }
    func copy() -> PackageShallowCopy {
        let clone = PackageShallowCopy()
        clone.box = box   // BUG: shares the box reference
        return clone
    }
}
