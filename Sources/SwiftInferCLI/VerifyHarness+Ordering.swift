import SwiftInferCore

extension VerifyHarness {

    /// Longest shared prefix first, identity hash ascending as the tiebreak.
    ///
    /// Prefix lengths are small integers over a candidate set that is usually
    /// short, so ties are the common case rather than the exception. Without
    /// the hash underneath, the entries a user is shown as "nearest" would be
    /// ordered by whatever `sorted(by:)` did with an incomparable pair.
    static func byDistanceDescendingThenIdentityHash(
        _ lhs: (entry: SemanticIndexEntry, distance: Int),
        _ rhs: (entry: SemanticIndexEntry, distance: Int)
    ) -> Bool {
        lhs.distance != rhs.distance
            ? lhs.distance > rhs.distance
            : lhs.entry.identityHash < rhs.entry.identityHash
    }
}
