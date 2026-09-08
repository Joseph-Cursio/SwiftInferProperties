/// Ordering over `[MutationMethod]`, named rather than inlined.
///
/// Three discoverers — `DefensiveCopyDiscoverer`, `StableIdentityDiscoverer`
/// and `ValueSemanticDiscoverer` — each built a mutation surface and sorted it
/// with the same two-key comparator written out in full. They were not found by
/// reading the three files; the linter derived a name from each closure's keys
/// and the same name came back three times.
///
/// The law is a **strict weak ordering**, and the tiebreak is what earns it.
/// Two overloads sharing a name are ordered by parameter count; without that,
/// `add(_:)` and `add(_:at:)` would be incomparable and their order left to a
/// `sorted(by:)` Swift does not promise is stable — so a mutation surface
/// rendered into a generated test could reorder between runs over identical
/// input.
enum MutationMethodOrdering {

    /// Name ascending, parameter count ascending as the tiebreak.
    static func byNameThenParameterCount(_ lhs: MutationMethod, _ rhs: MutationMethod) -> Bool {
        (lhs.name, lhs.parameterCount) < (rhs.name, rhs.parameterCount)
    }
}
