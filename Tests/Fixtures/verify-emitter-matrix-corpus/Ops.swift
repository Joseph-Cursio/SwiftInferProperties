// Trivially-CORRECT implementations, one per emitter matrix cell, so every
// emitted verify stub can be compiled AND run to bothPass. The point is coverage
// of the emitter's (template × carrier × call-shape) matrix — that each cell
// produces valid, correct Swift — NOT coverage of the laws themselves.

/// The free/static call shape: static methods over `Int` (a raw carrier the
/// strategist generates directly).
public enum FreeOps {

    /// binary, commutative + associative + idempotent (max).
    public static func maximum(_ lhs: Int, _ rhs: Int) -> Int { lhs > rhs ? lhs : rhs }

    /// unary involution — negating twice returns the original.
    public static func negated(_ value: Int) -> Int { -value }

    /// unary idempotent — `abs(abs(x)) == abs(x)`.
    public static func absolute(_ value: Int) -> Int { value < 0 ? -value : value }

    /// A 1-parameter free/static measure — `length(x) >= 0` (a cardinality).
    public static func length(_ value: Int) -> Int { value < 0 ? -value : value }

    /// A TUPLE carrier `(Int, Int)` — sort the pair, so applying it twice is a
    /// no-op (`ordered(ordered(t)) == ordered(t)`, genuinely idempotent). Proves
    /// the tuple generator's success path.
    public static func ordered(_ pair: (Int, Int)) -> (Int, Int) {
        pair.0 <= pair.1 ? pair : (pair.1, pair.0)
    }
}

/// The INSTANCE call shape over a generatable (`CaseIterable`) carrier — the
/// shape the receiver trampoline handles, and the cell that hid the latent
/// `{ $0.union($1) }` compile bug.
public enum Tri: CaseIterable, Sendable, Equatable {
    case lo, mid, hi

    /// instance binary operator — a bounded semilattice (max by rank), so
    /// commutative, associative, and idempotent. The receiver is the first
    /// operand: `a.union(b)`.
    public func union(_ other: Tri) -> Tri {
        rank >= other.rank ? self : other
    }

    /// instance unary involution — reflect around `mid` (`lo`↔`hi`, `mid` fixed),
    /// so `x.flipped().flipped() == x`.
    public func flipped() -> Tri {
        switch self {
        case .lo: return .hi
        case .mid: return .mid
        case .hi: return .lo
        }
    }

    /// The same involution as a read-only COMPUTED PROPERTY — recall epic #1:
    /// `x.mirrored.mirrored == x`, accessed without parentheses.
    public var mirrored: Tri { flipped() }

    /// A 0-parameter measure of `self` as a COMPUTED PROPERTY — `value.size >= 0`
    /// (the measure template's non-negativity law, computed-property shape).
    public var size: Int { rank + 1 }

    /// The same measure as a nullary METHOD — `value.width() >= 0`.
    public func width() -> Int { rank + 1 }

    private var rank: Int {
        switch self {
        case .lo: return 0
        case .mid: return 1
        case .hi: return 2
        }
    }
}
