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

    /// Parameter labels that name a **position**, not a role. Two operands called `lhs`
    /// and `rhs` are as interchangeable as two called `_` — the names say which side, not
    /// what for.
    ///
    /// **This set is the whole correction.** The first version of `isRoleDistinct` tested
    /// only that the labels *differ*, which is true of nearly every named pair, and it
    /// passed 5/5 on this repository purely because this repository does not write
    /// `+(lhs:rhs:)`. Run across the manifest it fired on the Swift standard library's
    /// `*(a:b:)` and `+(a:b:)` and on Foundation's `+(lhs:rhs:)` — genuinely commutative
    /// arithmetic, called role-distinct by a rule whose own doc comment listed `lhs`/`rhs`
    /// as symmetric. **The design was right and the implementation did not match it.**
    static let positionalLabels: Set<String> = [
        "lhs", "rhs", "a", "b", "x", "y", "left", "right", "first", "second", "other"
    ]

    /// **Labels, not bodies.** Two parameters with different external labels, neither a
    /// positional convention, are carrying roles rather than operands: `carrier:oracle:`
    /// names what each argument *is for*, while `lhs:rhs:` and `_:` name only position.
    ///
    /// A function with symmetric labels and asymmetric roles is missed, and that is the
    /// bound on the signal rather than a defect in it.
    static func isRoleDistinct(_ summary: FunctionSummary) -> Bool {
        let labels = summary.parameters.compactMap(\.label)
        guard labels.count >= 2, Set(labels).count == labels.count else { return false }
        return !labels.contains { positionalLabels.contains($0.lowercased()) }
    }

    /// **Every corpus the manifest resolves, not item 34's trio.** The first run of this
    /// census used three corpora and declined the class as *"5 rows, all in this repo"* —
    /// a self-only claim made without looking at swift-format, NIO, the Swift stdlib or
    /// SwiftProjectLint, all of which were on the machine. `CorpusManifest` exists because
    /// of that.
    static let readings: [Reading] = CorpusManifest.available.compactMap { corpus in
        guard let scanned = try? FunctionScanner.scanCorpus(directory: corpus.primaryRoot) else {
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
            corpus: "\(corpus.id) (\(corpus.swiftFileCount) files)",
            total: total,
            roleDistinct: roleRows.count,
            roleRows: roleRows.sorted()
        )
    }
}
