// Verify-ready ALGEBRAIC corpus — a curated bounded-lattice enum with static
// binary operations. Self-contained, like the interaction-family verify
// corpora, and a fresh public API surface for the algebraic measured-verify
// path. The frozen cycle27-surface (real libraries) has ZERO verifying
// commutativity/associativity — its picks were all filtered false positives —
// so this corpus is the first to demonstrate them measured-bothPass.
//
// `Confidence` is a public `CaseIterable` enum, so the strategist generates it
// via `Gen.element(of: Confidence.allCases).map { $0! }` (the `.caseIterable`
// strategy) — public + accessible cross-module, unlike a memberwise struct
// (whose synthesized init is internal, or whose user init suppresses synthesis
// → the strategist returns `.todo`).
//
// The commutativity/associativity templates key the carrier off the ENCLOSING
// type (`CommutativityTemplate`: `carrier: { $0.containingTypeName }`), so the
// operations are STATIC methods on `Confidence` — a free `(T,T)->T` has no
// enclosing type and resolves to `unsupported-carrier: (none)`.
//
// `(Confidence, Confidence) -> Confidence` surfaces as BOTH commutativity and
// associativity.

public enum Confidence: Int, CaseIterable, Comparable, Sendable {
    case low
    case medium
    case high

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Lattice join (least upper bound) — commutative + associative (and
    /// idempotent) → both bothPass.
    public static func join(_ a: Confidence, _ b: Confidence) -> Confidence {
        a >= b ? a : b
    }

    /// Lattice meet (greatest lower bound) — commutative + associative → both
    /// bothPass.
    public static func meet(_ a: Confidence, _ b: Confidence) -> Confidence {
        a <= b ? a : b
    }

    /// Returns `a` unless it's `.medium`, else `b` (a "first non-medium" fold).
    /// This is ASSOCIATIVE (assoc → bothPass) but NOT commutative
    /// (`leftBiased(low, high) == low` ≠ `leftBiased(high, low) == high`), so
    /// commutativity → measured-defaultFails. Both surface (the name isn't
    /// vocabulary-vetoed); execution distinguishes the two properties on one
    /// function — the deliberate false positive is the commutativity pick.
    public static func leftBiased(_ a: Confidence, _ b: Confidence) -> Confidence {
        a == .medium ? b : a
    }
}
