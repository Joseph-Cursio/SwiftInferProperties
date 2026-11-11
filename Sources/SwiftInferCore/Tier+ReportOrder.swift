public extension Tier {
    /// Canonical order for the `swift-infer report` tier breakdown:
    /// verified → strong → likely → possible → advisory → suppressed.
    ///
    /// Deliberately *not* `allCases.sorted()` — `severityRank` orders `suppressed` before
    /// `advisory`, whereas the report shows the two low tiers advisory-first. Derived by sorting
    /// `allCases` on `reportDisplayRank` (an exhaustive `switch`), so a new tier can never
    /// silently drop out of the breakdown, and the display labels come from `label` rather than
    /// a hand-kept parallel string list. `ReportRenderer` renders this via `.map(\.label)`.
    static var reportDisplayOrder: [Tier] {
        allCases.sorted { $0.reportDisplayRank < $1.reportDisplayRank }
    }

    /// The tiers at least as prominent as `floor`, in severity order.
    ///
    /// This is what a surface includes when its confidence threshold is lowered:
    /// `insights` and `report` include down to `.likely` by default, and
    /// `--include-possible` moves the floor to `.possible`. Expressed against
    /// `Comparable` (which orders by `severityRank`, `verified` minimum) so the
    /// membership follows from the tier ordering rather than from a hand-kept
    /// list of names — the call sites previously spelled out
    /// `["Verified", "Strong", "Likely"]` as string literals that had to match
    /// `label` exactly, in two places, with no compiler check.
    static func atLeastAsProminentAs(_ floor: Tier) -> [Tier] {
        allCases.filter { $0 <= floor }.sorted()
    }

    private var reportDisplayRank: Int {
        switch self {
        case .verified: return 0
        case .strong: return 1
        case .likely: return 2
        case .possible: return 3
        case .advisory: return 4
        case .suppressed: return 5
        }
    }
}
