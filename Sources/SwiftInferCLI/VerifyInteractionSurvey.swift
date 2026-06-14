import Foundation
import SwiftInferCore

/// Cycle 114 — the `verify-interaction --all` survey: discover every
/// interaction-invariant identity in a target, run measured verify against
/// each, record evidence, and render a per-identity outcome summary. This
/// is the campaign's "harvest" step — one command instead of N hand-pinned
/// `verify-interaction` runs — feeding `verify-evidence.json` so a later
/// `discover-interaction` surfaces the survivors at `.verified`.
///
/// **Serial by design (this cycle).** Each `runWithInvariant` spawns a real
/// `swift build` + run, so concurrency would help — but the interaction
/// verify workdir is keyed by *reducer* (`workdirSegment(for: candidate)`),
/// not per-invariant, so two identities on the same reducer share a workdir
/// and can't build concurrently without clobbering. The algebraic survey
/// gets bounded parallelism only because its workdirs are identity-hash-
/// keyed. Per-invariant workdir isolation (the prerequisite for a parallel
/// interaction survey) is a noted follow-up; serial is correct today.
/// Running serially also means `runWithInvariant`'s per-call evidence
/// record is race-free — no batch needed.
enum VerifyInteractionSurvey {

    /// One surveyed identity + its measured outcome.
    struct Entry: Equatable {
        let suggestion: InteractionInvariantSuggestion
        let result: InteractionVerifyOutcomeParser.Result
    }

    enum SurveyError: Error, CustomStringConvertible, Equatable {
        case unknownFamily(raw: String)

        var description: String {
            switch self {
            case let .unknownFamily(raw):
                let valid = InteractionInvariantFamily.allCases
                    .map(\.rawValue)
                    .joined(separator: ", ")
                return "swift-infer verify-interaction --all: unknown --family '\(raw)'. "
                    + "Valid families: \(valid)."
            }
        }
    }

    /// Full path: discover → optional family filter → serial measured verify
    /// (records evidence per identity) → rendered summary. Returns the
    /// summary string; the caller prints it.
    static func run(
        target: String,
        familyFilter: String?,
        sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
        userModuleName: String? = nil,
        workingDirectory: URL
    ) throws -> String {
        let all = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            target: target,
            workingDirectory: workingDirectory
        )
        let family = try parseFamily(familyFilter)
        let selected = family.map { chosen in all.filter { $0.family == chosen } } ?? all

        guard !selected.isEmpty else {
            return render(target: target, family: family, entries: [])
        }

        var entries: [Entry] = []
        for suggestion in selected {
            let result = try VerifyInteractionPipeline.runWithInvariant(
                target: target,
                invariant: suggestion,
                sequenceCount: sequenceCount,
                userModuleName: userModuleName,
                workingDirectory: workingDirectory
            )
            entries.append(Entry(suggestion: suggestion, result: result))
        }
        return render(target: target, family: family, entries: entries)
    }

    /// Parse the optional `--family` filter into a family, throwing on an
    /// unknown value. `nil` (no filter) passes through.
    static func parseFamily(_ raw: String?) throws -> InteractionInvariantFamily? {
        guard let raw else { return nil }
        guard let family = InteractionInvariantFamily(rawValue: raw) else {
            throw SurveyError.unknownFamily(raw: raw)
        }
        return family
    }

    // MARK: - Rendering (pure)

    static func render(
        target: String,
        family: InteractionInvariantFamily?,
        entries: [Entry]
    ) -> String {
        let header = "swift-infer verify-interaction --all — V2.0 survey of '\(target)'"
        guard !entries.isEmpty else {
            return header + "\n"
                + "  0 interaction-invariant identities\(familyNote(family)) — nothing to verify.\n"
        }
        var lines = [
            header,
            "  Identities: \(entries.count)\(familyNote(family))",
            ""
        ]
        for entry in entries {
            lines.append(line(for: entry))
        }
        lines.append("")
        lines.append("  Summary: \(tally(entries))")
        lines.append(
            "  Evidence recorded to .swiftinfer/verify-evidence.json (\(entries.count) identities)."
        )
        return lines.joined(separator: "\n") + "\n"
    }

    private static func familyNote(_ family: InteractionInvariantFamily?) -> String {
        family.map { " (--family \($0.rawValue))" } ?? ""
    }

    private static func line(for entry: Entry) -> String {
        let outcome = "[\(entry.result.outcome.rawValue)]".padding(
            toLength: 34,
            withPad: " ",
            startingAt: 0
        )
        let detail = entry.result.detail.map { " — \($0)" } ?? ""
        return "  \(outcome) \(entry.suggestion.reducerQualifiedName)  "
            + "\(entry.suggestion.family.rawValue)  \(entry.suggestion.predicate)\(detail)"
    }

    /// Compact count-by-outcome tally in canonical outcome order, showing
    /// only outcomes that occurred.
    private static func tally(_ entries: [Entry]) -> String {
        let counts = VerifyEvidenceOutcome.allCases.compactMap { outcome -> String? in
            let count = entries.filter { $0.result.outcome == outcome }.count
            return count == 0 ? nil : "\(count) \(outcome.rawValue)"
        }
        return counts.joined(separator: ", ")
    }
}
