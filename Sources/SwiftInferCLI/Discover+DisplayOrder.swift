import SwiftInferCore

/// Display order for `discover`'s default surface.
///
/// Split from `Discover+Pipeline.swift` on the 400-line file cap. The rule is
/// one comparator, but the reason it exists is worth its own file: two
/// deliberate, well-argued decisions had drifted into a contradiction, and the
/// resolution turned out to cost nothing.
extension SwiftInferCommand.Discover {

    /// Display order for the default surface: **strongest law first**.
    ///
    /// Two deliberate decisions had drifted into a contradiction here, and both
    /// are right — so the fix is ordering, not hiding.
    ///
    /// `PredicateTemplate` scores totality at 20, the catalogue's lowest,
    /// arguing that surfacing it by default "would bury the partition and
    /// comparator findings under a list of everything that returns a `Bool`,
    /// and a category that fires on everything is a category people switch
    /// off." Then `3e38e34` ruled that **a law the code OWES is never hidden**
    /// — earned from a real regression where a reader complied with the linter
    /// and the sharpest law in the run vanished — and put `predicate` in
    /// `roleEntailedTemplates`, so the rescue surfaces it below the cut.
    ///
    /// Measured on this repo before this change: `SwiftInferTemplates`
    /// rendered **56 score-20 predicates before the first score-80 finding**,
    /// and 46 of 77 on `SwiftInferCore`. That is precisely the burial B3 named,
    /// arriving through the door `3e38e34` opened for good reasons.
    ///
    /// Sorting resolves it with nothing given up: an owed law stays visible,
    /// and it stays *below* every law the reader came for. `query` already
    /// ordered by score descending; `discover` — the primary surface — did not.
    ///
    /// **Total and deterministic**, because PRD §16 #6 requires byte-identical
    /// output across runs: `sorted(by:)` is not a stable sort, so equal scores
    /// break ties on the identity hash rather than on whatever order the
    /// templates happened to produce.
    static func strongestFirst(_ lhs: Suggestion, _ rhs: Suggestion) -> Bool {
        if lhs.score.total != rhs.score.total {
            return lhs.score.total > rhs.score.total
        }
        return lhs.identity.normalized < rhs.identity.normalized
    }
}
