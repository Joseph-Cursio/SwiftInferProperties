/// Ordering over `[InteractionInvariantSuggestion]`, named rather than inlined.
///
/// Three call sites across two modules carried this comparator byte-for-byte:
/// `DiscoverInteractionCommand`'s convention-role and view-model merges, and
/// `InteractionTemplateEngine.analyze`. All three build a suggestion list from
/// two sources and hand the reader the strongest first.
///
/// The tiebreak is the part worth naming. Scores are small integers and
/// collide constantly, so without `identity.normalized` underneath, most of
/// this list would be incomparable and its order would fall to a `sorted(by:)`
/// Swift does not promise is stable — meaning two runs over an unchanged tree
/// could emit the same suggestions in a different order, and a diff of the
/// output would show work that did not happen.
public enum InteractionSuggestionOrdering {

    /// Strongest score first, normalized identity ascending as the tiebreak.
    public static func byScoreDescendingThenIdentity(
        _ lhs: InteractionInvariantSuggestion,
        _ rhs: InteractionInvariantSuggestion
    ) -> Bool {
        lhs.score != rhs.score
            ? lhs.score > rhs.score
            : lhs.identity.normalized < rhs.identity.normalized
    }
}
