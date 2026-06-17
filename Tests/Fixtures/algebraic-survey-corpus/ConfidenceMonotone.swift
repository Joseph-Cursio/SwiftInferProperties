// Widens the algebraic corpus to the MONOTONICITY family — `f: T -> U`
// where `U` is an ordered codomain and `a <= b ⟹ f(a) <= f(b)`. This is
// the fifth measured algebraic family the corpus demonstrates (after
// commutativity / associativity / idempotence / round-trip).
//
// Why these fit cleanly on the EXISTING `Confidence` carrier:
//
//   - `MonotonicityTemplate` surfaces any single-param, non-mutating
//     function whose return type is a curated ordered codomain
//     (`Int` / `Double` / `Float` / `String` / `Date` / `Duration`).
//     Both projections return `Int`. A curated name (`score`,
//     `priority` are `MonotonicityTemplate.curatedVerbs`) adds a +10
//     name signal on top of the +25 codomain baseline.
//
//   - The carrier is the ENCLOSING type (`carrier: { $0.containingTypeName }`),
//     and the verifier generates two carrier values, sorts them by the
//     carrier's `Comparable`, then asserts `f(a) <= f(b)`. Declaring
//     these as STATIC methods on `Confidence` (already `Comparable` +
//     `CaseIterable`) makes carrier == input type, so generation +
//     sorting + the property all resolve against one type.
//
//   - Neither is an endomorphism `(T) -> T` (idempotence never fires),
//     neither is binary `(T, T) -> T` (no commutativity / associativity),
//     and neither pairs with an `Int -> Confidence` partner (no
//     round-trip / inverse-pair). Net surface: exactly TWO new picks —
//     one true positive + one deliberate false positive, the corpus's
//     per-family convention.

extension Confidence {
    /// Strictly-increasing projection to an Int score — order-preserving
    /// (`low < medium < high ⟹ 0 < 10 < 25`), so `score(a) <= score(b)`
    /// whenever `a <= b` → measured-bothPass.
    public static func score(_ confidence: Confidence) -> Int {
        switch confidence {
        case .low: return 0
        case .medium: return 10
        case .high: return 25
        }
    }

    /// A curated-named projection (`priority` is a monotonicity verb)
    /// that is NOT order-preserving: `.medium` outranks `.high`, so
    /// `priority(.medium) == 9 > priority(.high) == 5` while
    /// `.medium < .high`. The template surfaces it on name + codomain,
    /// and only execution disproves it → the deliberate monotonicity
    /// false positive (measured-defaultFails).
    public static func priority(_ confidence: Confidence) -> Int {
        switch confidence {
        case .low: return 0
        case .medium: return 9
        case .high: return 5
        }
    }
}
