import Foundation

/// The two arms. They differ in **one line** and test opposite halves of the catalog.
///
/// ## Arm A — score only. A PREORDER, not a total order.
///
/// Two players who both bowled 214 are interchangeable, so the sort result is determined
/// only *up to permutation within tie groups*. That makes three things measurable:
///
/// - **stability** — an unstable sort and a stable one disagree, on ties only
/// - **the model law** — `sort(xs).map(\.score)` agrees even when `sort(xs)` does not,
///   which is `fixtures/equatable-signal`'s recorded advice ("propose the model law, not
///   the Equatable laws, for projections") stated in ten lines
/// - **the collision trap** — a tie IS a collision, and CLAUDE.md's rule is that any
///   property whose failure needs two generated values to collide is invisible to a
///   generator drawing from a wide domain
///
/// ## Arm B — score desc, then name asc. A TOTAL order (given unique names).
///
/// Every correct implementation now produces the identical array, so stability stops
/// mattering and the differential law becomes a clean oracle instead. What arm B buys is
/// the **comparator** itself: a two-key comparator is where strict-weak-ordering bugs
/// actually live, and `brokenDisjunctive` below is the canonical one.
///
/// **Arm B depends on arm A's absence.** The order is total only because names are unique
/// (`Leaderboard.namesAreUnique`). If that invariant breaks, arm B silently degrades into
/// arm A. Nothing in the catalog models one law being a precondition for another — every
/// suggestion is independent — so that dependency is a structural gap, not a missing
/// template. README §5.
public enum Comparators {

    /// Arm A. A valid strict weak ordering *on the score projection*, and only a preorder
    /// on `PlayerScore`.
    public static func byScoreDescending(_ lhs: PlayerScore, _ rhs: PlayerScore) -> Bool {
        lhs.score > rhs.score
    }

    /// Arm B. Lexicographic, written the way that is actually transitive.
    public static func byScoreThenName(_ lhs: PlayerScore, _ rhs: PlayerScore) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.name < rhs.name
    }

    /// **Mutant.** The canonical strict-weak-ordering violation: `||` instead of a
    /// tie-break. It is not transitive, and Swift's sort is entitled to trap on it
    /// ("not a strict weak ordering") or to produce garbage.
    ///
    /// Concretely, with `a = (n: "z", 5)`, `b = (n: "a", 3)`, `c = (n: "m", 4)`:
    /// `less(b, c)` is true (`"a" < "m"`), `less(c, a)` is true (`"m" < "z"`), and
    /// `less(b, a)` is true — but `less(a, b)` is ALSO true (`5 > 3`), so the relation is
    /// not asymmetric and the sort's invariants are void.
    public static func brokenDisjunctive(_ lhs: PlayerScore, _ rhs: PlayerScore) -> Bool {
        lhs.score > rhs.score || lhs.name < rhs.name
    }

    /// **Mutant.** `>=` is reflexive, so `less(x, x)` is true. Not a strict weak ordering;
    /// Swift traps.
    public static func nonStrict(_ lhs: PlayerScore, _ rhs: PlayerScore) -> Bool {
        lhs.score >= rhs.score
    }
}
