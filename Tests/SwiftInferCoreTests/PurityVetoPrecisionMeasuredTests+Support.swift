import Foundation

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// The answer key and the arms for `PurityVetoPrecisionMeasuredTests`. Split out only for
/// the 400-line file cap; the reasoning that governs both lives in that suite's header.
extension PurityVetoPrecisionMeasuredTests {

    // MARK: - The answer key

    struct SurveyRow {
        let outcome: String
        let template: String
        let function: String
    }

    /// The recorded whole-corpus survey, keyed by `identityHash`.
    static let survey: [String: SurveyRow] = {
        let path = PurityRefutationCensusMeasuredTests.packageRoot
            .appendingPathComponent("fixtures/whole-corpus-survey/2026-08-05-whole-corpus.jsonl")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return [:] }

        var rows: [String: SurveyRow] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hash = object["identityHash"] as? String,
                  let outcome = object["outcome"] as? String else { continue }
            rows[hash] = SurveyRow(
                outcome: outcome,
                template: object["templateName"] as? String ?? "?",
                function: object["primaryFunctionName"] as? String ?? "?"
            )
        }
        return rows
    }()

    /// A recorded outcome, reduced to what it says about *removing* the law.
    enum Cost: String, CaseIterable {
        /// The law found a counterexample. Removing it is an unambiguous loss.
        case refuted
        /// The law ran and did not refute. Ambiguous — see the suite header.
        case passed
        /// It never ran, so removing it costs nothing measurable.
        case inert
        /// Not in the survey at all — the corpus has moved since 2026-08-05.
        case unrecorded

        init(outcome: String?) {
            switch outcome {
            case "measured-defaultFails": self = .refuted
            case "measured-bothPass": self = .passed
            case .some: self = .inert
            case nil: self = .unrecorded
            }
        }
    }

    // MARK: - The arms

    /// One suggestion the veto would remove, and what the answer key says it was worth.
    struct Removal {
        let identity: String
        let template: String
        let subject: String
        let cost: Cost
        /// True when the refutation names a construct — the narrow scope's population.
        let witnessBearing: Bool
    }

    struct Arm {
        let suggestions: Int
        let recorded: Int
        let removals: [Removal]

        var narrow: [Removal] { removals.filter(\.witnessBearing) }
    }

    static func counts(_ rows: [Removal]) -> [Cost: Int] {
        Dictionary(grouping: rows, by: \.cost).mapValues(\.count)
    }

    static func render(_ counts: [Cost: Int]) -> String {
        Cost.allCases.map { "\($0.rawValue) \(counts[$0] ?? 0)" }.joined(separator: " · ")
    }

    /// Self only: it is the corpus the survey was taken over.
    static let measured: Arm = {
        let root = PurityRefutationCensusMeasuredTests.packageRoot.appendingPathComponent("Sources")
        guard let scanned = try? FunctionScanner.scanCorpus(directory: root) else {
            return Arm(suggestions: 0, recorded: 0, removals: [])
        }
        let suggestions = TemplateRegistry.discover(
            in: scanned.summaries, identities: scanned.identities, typeDecls: scanned.typeDecls
        )
        return Arm(
            suggestions: suggestions.count,
            recorded: suggestions.filter { survey[$0.identity.display] != nil }.count,
            removals: removals(from: suggestions, in: scanned)
        )
    }()

    private static func removals(
        from suggestions: [Suggestion],
        in scanned: ScannedCorpus
    ) -> [Removal] {
        let summaryAt = Dictionary(scanned.summaries.map { ($0.location, $0) }) { first, _ in first }

        // `PackagePurityJoin`'s own rule, reused rather than restated — which is what makes
        // "witness-bearing" here mean the same thing the shipped veto would mean by it.
        let refutingNames = PackagePurityJoin.refutingNames(in: scanned.summaries)

        return suggestions.compactMap { suggestion in
            let refutedSubjects = suggestion.evidence.compactMap { row -> FunctionSummary? in
                guard let summary = summaryAt[row.location], summary.purityVerdict == .refuted else {
                    return nil
                }
                return summary
            }
            guard !refutedSubjects.isEmpty else { return nil }

            // **The shipped rule.** A `.refuted` declaration that does not throw cannot be
            // an ignorance-only refutation: `propagatedTry` requires a `throws` clause by
            // definition and `noBody` is structurally unreachable. A subject retracted BY
            // the join carries a witness one hop away, which the name set catches.
            let witnessBearing = refutedSubjects.contains { subject in
                !subject.isThrows
                    || subject.calledFreeFunctionNames.contains(where: refutingNames.contains)
            }
            return Removal(
                identity: suggestion.identity.display,
                template: suggestion.templateName,
                subject: refutedSubjects.map(\.name).joined(separator: " + "),
                cost: Cost(outcome: survey[suggestion.identity.display]?.outcome),
                witnessBearing: witnessBearing
            )
        }
    }
}
