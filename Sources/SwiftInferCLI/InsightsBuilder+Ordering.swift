extension InsightsBuilder {

    /// Largest group first, structure label ascending as the tiebreak.
    static func byMemberCountDescendingThenStructure(
        _ lhs: InsightsGroup, _ rhs: InsightsGroup
    ) -> Bool {
        lhs.members.count != rhs.members.count
            ? lhs.members.count > rhs.members.count
            : lhs.structure < rhs.structure
    }
}
