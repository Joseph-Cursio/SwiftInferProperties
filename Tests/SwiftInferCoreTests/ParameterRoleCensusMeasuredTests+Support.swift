import Foundation

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// The label split for `ParameterRoleCensusMeasuredTests`. Split out only for the
/// 400-line file cap; the reasoning lives in that suite's header.
extension ParameterRoleCensusMeasuredTests {

    struct Reading {
        let corpus: String
        let total: Int
        let roleDistinct: Int
        let roleRows: [String]
    }

    /// **Labels, not bodies.** Two parameters with different external labels, neither of
    /// them `_`, are carrying roles rather than operands: `carrier:oracle:` names what each
    /// argument *is for*, while `lhs:rhs:` and `_:` name only their position.
    ///
    /// A function with symmetric labels and asymmetric roles is missed, and that is the
    /// bound on the signal rather than a defect in it.
    static func isRoleDistinct(_ summary: FunctionSummary) -> Bool {
        let labels = summary.parameters.compactMap(\.label)
        guard labels.count >= 2 else { return false }
        return Set(labels).count == labels.count
    }

    static let readings: [Reading] = PartialPurityConsumerMeasuredTests.corpora.compactMap { corpus in
        guard let scanned = try? FunctionScanner.scanCorpus(directory: corpus.root) else {
            return nil
        }
        let suggestions = TemplateRegistry.discover(
            in: scanned.summaries, identities: scanned.identities, typeDecls: scanned.typeDecls
        )
        let summaryAt = Dictionary(scanned.summaries.map { ($0.location, $0) }) { first, _ in first }

        var total = 0
        var roleRows: [String] = []
        for suggestion in suggestions
        where binaryOperatorTemplates.contains(suggestion.templateName) {
            total += 1
            guard let row = suggestion.evidence.first,
                  let summary = summaryAt[row.location],
                  isRoleDistinct(summary) else { continue }
            let labels = summary.parameters.compactMap(\.label).joined(separator: ":")
            roleRows.append("\(suggestion.templateName) :: \(summary.name)(\(labels):)")
        }
        return Reading(
            corpus: corpus.name,
            total: total,
            roleDistinct: roleRows.count,
            roleRows: roleRows.sorted()
        )
    }
}
