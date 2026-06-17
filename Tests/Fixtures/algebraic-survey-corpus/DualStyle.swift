// Widens the algebraic corpus to the DUAL-STYLE-CONSISTENCY family —
// a non-mutating `func op'() -> Self` and its mutating twin
// `mutating func op()` must agree: `x.op'() == { var c = x; c.op(); c }`.
// This is the sixth measured template the corpus demonstrates and the
// first dual-style pick verified on a CUSTOM (non-OrderedCollections)
// carrier — the prior measured dual-style coverage was stdlib-only.
//
// Why `reverse` / `reversed` on a two-state enum:
//
//   - `DualStylePairing` requires a curated (mutating, non-mutating)
//     name pair on the SAME type with matching parameter lists, the
//     non-mutating half returning `Self`. `reverse` ↔ `reversed`
//     satisfies the active-to-past-participle rule and is in
//     `DualStyleConsistencyPairResolver.curated`, so no resolver-table
//     change is needed.
//
//   - The carrier is the enclosing type; a public `CaseIterable` enum
//     generates via `.caseIterable`. Both methods are 0-arg instance
//     methods, so the verifier (after the non-OC instance-call-shape
//     fix in `StrategistDispatchEmitter+Templates`) checks
//     `original.reversed()` against `{ var c = original; c.reverse(); c }`.
//
//   - Per the corpus convention each family carries a true positive +
//     a deliberate false positive; execution decides.

public enum Toggle: Int, CaseIterable, Equatable, Sendable {
    case off
    case on

    /// Flip in place — the mutating half.
    public mutating func reverse() {
        self = (self == .off) ? .on : .off
    }

    /// The non-mutating twin — returns the flipped copy WITHOUT mutating.
    /// Agrees with `reverse()` by construction (both flip the state), so
    /// `original.reversed() == { var c = original; c.reverse(); c }`
    /// → measured-bothPass.
    public func reversed() -> Toggle {
        (self == .off) ? .on : .off
    }
}

public enum Latch: Int, CaseIterable, Equatable, Sendable {
    case open
    case closed

    /// Flip in place — the mutating half (correct).
    public mutating func reverse() {
        self = (self == .open) ? .closed : .open
    }

    /// The non-mutating twin is BUGGY — it returns `self` unchanged
    /// instead of the flipped copy. The dual-style template surfaces it
    /// on the `reverse`/`reversed` name pair, and only execution
    /// disproves it: `original.reversed() == original` but
    /// `{ var c = original; c.reverse(); c }` is flipped → the deliberate
    /// dual-style false positive (measured-defaultFails).
    public func reversed() -> Latch {
        self
    }
}
