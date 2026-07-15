// Verify-ready true positives for the three algebraic-law templates wired for
// measured verify (involution / binary-idempotence / homomorphism). Static
// methods on a public type so each has a carrier the verifier can qualify the
// call with (`Laws.negated(…)`); the names still match the templates' free/static
// `(T) -> T` / `(T, T) -> T` / `[T] -> Int` shapes.
public enum Laws {

    /// involution — negating twice returns the original: `negated(negated(x)) == x`.
    public static func negated(_ value: Int) -> Int { -value }

    /// binary-idempotence — combining a value with itself is a no-op:
    /// `maximum(x, x) == x`.
    public static func maximum(_ lhs: Int, _ rhs: Int) -> Int { lhs > rhs ? lhs : rhs }

    /// homomorphism — the tally (element count) is additive over concatenation:
    /// `tally(a + b) == tally(a) + tally(b)`.
    public static func tally(_ items: [Int]) -> Int { items.count }

    /// multiplicative-homomorphism — absolute value is multiplicative:
    /// `abs(a * b) == abs(a) * abs(b)`.
    public static func magnitude(_ value: Int) -> Int { value < 0 ? -value : value }
}

/// An INSTANCE binary operator over a generatable (`CaseIterable`) carrier —
/// proves the 2026-07 instance-op recall widening end-to-end: `x.union(y)` fires
/// binary-idempotence / commutativity / associativity, and the verifier drives it
/// through the `{ $0.union($1) }` receiver trampoline. Logical OR is a
/// semilattice, so all three hold.
public enum Flag: CaseIterable, Equatable, Sendable {
    case off, on

    /// `union(x, x) == x`, commutative, associative — a bounded semilattice.
    public func union(_ other: Flag) -> Flag {
        (self == .on || other == .on) ? .on : .off
    }
}
