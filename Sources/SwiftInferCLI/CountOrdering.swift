/// Orderings over `[String: Int]` count tables, named rather than inlined.
///
/// Two call sites carried this comparator byte-for-byte —
/// `ReportRenderer.countBreakdown` and
/// `SuggestRefactors.formatTemplateCounts` — and a third states the same
/// intent in prose: *"Sort by count descending, then by name ascending for
/// stability across runs."* Naming it once puts that sentence in the type
/// system instead of in three places.
///
/// **Why these are worth naming and `$0.key < $1.key` is not.** A comparator
/// over one `Comparable` field inherits irreflexivity, asymmetry and
/// transitivity from that field and cannot violate them; the closure is also
/// already self-describing, so a name adds a hop and no information. A two-key
/// comparator can violate them, and the name carries something the body does
/// not — that a tiebreak exists at all.
///
/// The law these owe is a **strict weak ordering**, not a total one. Two
/// entries sharing a count and a name are incomparable, `sorted(by:)` is not
/// guaranteed stable in Swift, and the tiebreak is precisely what stops that
/// mattering here.
enum CountOrdering {

    /// Commonest first, name ascending as the tiebreak.
    static func byCountDescendingThenName(
        _ lhs: (key: String, value: Int),
        _ rhs: (key: String, value: Int)
    ) -> Bool {
        lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
    }
}
