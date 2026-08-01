import Foundation

/// The **member form** — the primary subject. `sortedByScore` in `Sorts.swift` is the
/// free-function control.
///
/// ## The cache is deliberate
///
/// A *computed* `var sorted: [PlayerScore] { entries.sorted(...) }` gives you
/// `board.sorted == board.sorted`, which is `f(x) == f(x)`: it passes "did discovery
/// return > 0" and **cannot fail**. The repo's own rule is to score refutability rather
/// than suggestion count, so a computed property would make this fixture measure nothing.
///
/// A *stored* cache invalidated on mutation gives a coherence invariant instead — after
/// `add`, the cache must reflect the new entry — which is a real bug class and refutable.
/// `staleCache` below is the mutant.
public struct Leaderboard: Equatable, Sendable {

    private var entries: [PlayerScore]
    private var cachedSorted: [PlayerScore]?

    /// When `true`, `add` forgets to invalidate — the stale-cache mutant.
    private let staleCache: Bool

    public init(entries: [PlayerScore] = [], staleCache: Bool = false) {
        self.entries = entries
        self.staleCache = staleCache
        self.cachedSorted = nil
    }

    public var count: Int { entries.count }

    public var all: [PlayerScore] { entries }

    /// High to low. Arm B's total order, so the result is unique.
    public mutating func sorted() -> [PlayerScore] {
        if let cachedSorted { return cachedSorted }
        let result = entries.sorted(by: Comparators.byScoreThenName)
        cachedSorted = result
        return result
    }

    /// Arm A — the preorder. Separate entry point so both arms are reachable from the
    /// same carrier without two types.
    public func sortedByScoreOnly() -> [PlayerScore] {
        entries.sorted(by: Comparators.byScoreDescending)
    }

    public mutating func add(_ entry: PlayerScore) {
        entries.append(entry)
        if !staleCache { cachedSorted = nil }
    }

    /// **Each player plays one game**, so this must hold for every reachable board.
    ///
    /// It is not decoration: arm B's comparator is a TOTAL order only because names are
    /// unique. Break this and `sorted()` degrades to arm A's preorder silently — the
    /// result stays sorted, it just stops being unique, and every ordering law still
    /// passes.
    ///
    /// The same `Set(xs).count == xs.count` shape `discover` already finds in this repo
    /// ("Test body asserts `Set(labels).count == labels.count`",
    /// `invariant-preservation`).
    public var namesAreUnique: Bool {
        Set(entries.map(\.name)).count == entries.count
    }
}
