import Foundation

/// Foundation laws — `Data` (a `RangeReplaceableCollection` of bytes, with a
/// base64 round-trip) and `IndexSet` (a `SetAlgebra` of non-negative indices).
/// Foundation is available to the `swift` interpreter, so these carry NO
/// `imports` and run on the fast path alongside the standard-library laws.
extension StandardLibraryProperties {

    static let foundationLaws: [KnownProperty] = [
        law(
            "Data", "base64 round-trip", "Data(base64Encoded: d.base64EncodedString()) == d",
            "let d = Data(randArr().map { UInt8($0 & 255) }); "
                + "return Data(base64Encoded: d.base64EncodedString()) == d",
            template: "round-trip"
        ),
        law(
            "Data", "count is additive over append", "append(y) grows count by y.count",
            "let xbytes = randArr().map { UInt8($0 & 255) }, ybytes = randArr().map { UInt8($0 & 255) }; "
                + "var d = Data(xbytes); d.append(contentsOf: ybytes); "
                + "return d.count == xbytes.count + ybytes.count"
        ),
        law(
            "IndexSet", "commutative under union", "a.union(b) == b.union(a)",
            "let a = IndexSet(randArr().map { abs($0) }), b = IndexSet(randArr().map { abs($0) }); "
                + "return a.union(b) == b.union(a)",
            witnesses: "Semilattice", template: "commutativity"
        ),
        law(
            "IndexSet", "idempotent under union", "a.union(a) == a",
            "let a = IndexSet(randArr().map { abs($0) }); return a.union(a) == a",
            witnesses: "Semilattice"
        )
    ]
}
