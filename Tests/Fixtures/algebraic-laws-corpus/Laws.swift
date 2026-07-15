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
}
