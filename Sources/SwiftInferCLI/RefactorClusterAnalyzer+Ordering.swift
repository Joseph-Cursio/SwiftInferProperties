import Foundation
import SwiftInferCore

extension RefactorClusterAnalyzer {

    /// Count ascending, tie-breaker index descending — written for `max(by:)`,
    /// which takes the **greatest** element under this ordering, so the winner
    /// is the highest count and, among ties, the lowest tie-breaker index.
    ///
    /// The direction reads backwards for that reason, and the name states the
    /// ordering rather than the selection because that is what the laws are
    /// about: it must still be irreflexive, asymmetric and transitive, and
    /// `max(by:)` is undefined if it is not.
    static func byCountThenTieBreakerIndexDescending(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        lhs.count != rhs.count
            ? lhs.count < rhs.count
            : lhs.tieBreakerIndex > rhs.tieBreakerIndex
    }
}
