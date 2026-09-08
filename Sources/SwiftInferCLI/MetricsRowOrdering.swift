/// Ordering over `MetricsRenderer`'s per-template report rows.
///
/// Three rows in three files sorted the same way — `TemplateRow` and
/// `PostAcceptanceFailureRow` by `total`, `TimeToAdoptionRow` by `count`. The
/// differing field name is why the duplication survived three files: nothing a
/// reader greps for matches all three, and the linter's derived names
/// (`byTotalDescendingThenTemplate`, `byCountDescendingThenTemplate`) differed
/// for the same reason.
///
/// `rankingCount` is declared here rather than on the row types because it is a
/// fact about *this ranking*, not about the rows — a report sorted by failure
/// rate would want a different one, and the row should not have to guess.
///
/// The tiebreak matters more here than in most of these: template names are the
/// stable thing in a metrics report, counts collide constantly, and a report
/// whose rows reorder between runs over identical input reads as movement that
/// did not happen.
protocol TemplateRankedRow {
    var template: String { get }
    /// The magnitude this report ranks by — `total` for most rows, `count`
    /// where the row counts adoptions rather than decisions.
    var rankingCount: Int { get }
}

extension MetricsRenderer.TemplateRow: TemplateRankedRow {
    var rankingCount: Int { total }
}

extension MetricsRenderer.PostAcceptanceFailureRow: TemplateRankedRow {
    var rankingCount: Int { total }
}

extension MetricsRenderer.TimeToAdoptionRow: TemplateRankedRow {
    var rankingCount: Int { count }
}

enum MetricsRowOrdering {

    /// Busiest first, template name ascending as the tiebreak.
    static func byCountDescendingThenTemplate<Row: TemplateRankedRow>(
        _ lhs: Row, _ rhs: Row
    ) -> Bool {
        lhs.rankingCount != rhs.rankingCount
            ? lhs.rankingCount > rhs.rankingCount
            : lhs.template < rhs.template
    }
}
