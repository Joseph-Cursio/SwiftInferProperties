import Foundation
import SwiftInferCore

extension SurveyRunDiff {

    /// Subject ascending, template ascending as the tiebreak — one subject can
    /// change under several templates, and a diff that reorders them between
    /// runs reads as churn that did not happen.
    static func bySubjectThenTemplate(_ lhs: ChangedRow, _ rhs: ChangedRow) -> Bool {
        (lhs.subject, lhs.template) < (rhs.subject, rhs.template)
    }
}
