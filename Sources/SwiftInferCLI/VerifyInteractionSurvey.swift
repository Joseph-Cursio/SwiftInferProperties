import Foundation
import SwiftInferCore

/// Cycle 114 — the `verify-interaction --all` survey: discover every
/// interaction-invariant identity in a target, run measured verify against
/// each, record evidence, and render a per-identity outcome summary. This
/// is the campaign's "harvest" step — one command instead of N hand-pinned
/// `verify-interaction` runs — feeding `verify-evidence.json` so a later
/// `discover-interaction` surfaces the survivors at `.verified`.
///
/// **Bounded-parallel (cycle 120).** The fan-out builds up to
/// `maxParallel` identities concurrently (`withTaskGroup`, mirroring the
/// algebraic `--all-from-index` survey). Three pieces make it safe:
/// milestone 1's per-invariant workdir (`workdirSegment(for:identity:)`)
/// so sibling identities on one reducer no longer share a `.build/`;
/// milestone 2's `persistEvidence: false` + single batch write so
/// concurrent verifies can't lose records to interleaved
/// read-modify-writes; and a re-sort to discovery order so output stays
/// deterministic despite nondeterministic completion. Each task is a real
/// `swift build`, so the cap is conservative (default 4) — concurrent
/// builds contend for cores.
enum VerifyInteractionSurvey {

    /// One surveyed identity + its measured outcome.
    struct Entry: Equatable, Sendable {
        let suggestion: InteractionInvariantSuggestion
        let result: InteractionVerifyOutcomeParser.Result
    }

    /// Per-run verify config shared by every identity's worker. Bundled
    /// (rather than threaded as loose params) so the fan-out helpers stay
    /// under SwiftLint's parameter-count cap; `Sendable` so it can cross
    /// the `TaskGroup` boundary.
    struct RunContext: Sendable {
        let target: String
        let sequenceCount: Int
        let userModuleName: String?
        let workingDirectory: URL
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

    /// Full path: discover → optional family filter → bounded-parallel
    /// measured verify → batch-record evidence once → rendered summary.
    /// Returns the summary string; the caller prints it. `maxParallel`
    /// bounds in-flight `swift build`s (default 4, as the algebraic
    /// `--all-from-index` survey).
    static func run(
        target: String,
        familyFilter: String?,
        sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
        userModuleName: String? = nil,
        maxParallel: Int = 4,
        workingDirectory: URL
    ) async throws -> String {
        let all = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            target: target,
            workingDirectory: workingDirectory
        )
        let family = try parseFamily(familyFilter)
        let selected = family.map { chosen in all.filter { $0.family == chosen } } ?? all

        guard !selected.isEmpty else {
            return render(target: target, family: family, entries: [])
        }

        let context = RunContext(
            target: target,
            sequenceCount: sequenceCount,
            userModuleName: userModuleName,
            workingDirectory: workingDirectory
        )
        let entries = await runSurvey(
            selected: selected,
            context: context,
            parallelism: max(1, maxParallel)
        )
        // Cycle 120 — one batch write after the fan-out joins, so concurrent
        // verifies never lose records to an interleaved read-modify-write.
        VerifyInteractionPipeline.recordEvidenceBatch(
            entries.map { (invariant: $0.suggestion, result: $0.result) },
            workingDirectory: workingDirectory
        )
        return render(target: target, family: family, entries: entries)
    }

    /// Cycle 120 — bounded-parallel fan-out over the selected identities
    /// (mirrors the algebraic `runParallelSurvey`: prime `parallelism`
    /// tasks, then drain-and-refill). Each identity now builds in its own
    /// per-invariant workdir (milestone 1) and suppresses per-call
    /// recording (milestone 2), so the concurrency is safe. Task
    /// completion order is nondeterministic, so results are re-sorted to
    /// discovery order before return — the rendered summary and the
    /// batch-record order stay deterministic regardless of build timing.
    private static func runSurvey(
        selected: [InteractionInvariantSuggestion],
        context: RunContext,
        parallelism: Int
    ) async -> [Entry] {
        var collected: [(index: Int, entry: Entry)] = []
        await withTaskGroup(of: (index: Int, entry: Entry).self) { group in
            var inFlight = 0
            var nextIndex = 0
            func submitNext() {
                let index = nextIndex
                let suggestion = selected[index]
                nextIndex += 1
                inFlight += 1
                group.addTask { (index, surveyOne(suggestion: suggestion, context: context)) }
            }
            while nextIndex < selected.count, inFlight < parallelism { submitNext() }
            while let done = await group.next() {
                inFlight -= 1
                collected.append(done)
                if nextIndex < selected.count { submitNext() }
            }
        }
        return collected.sorted { $0.index < $1.index }.map(\.entry)
    }

    /// Per-identity worker. Runs the full measured verify; maps any thrown
    /// error to a `.measuredError` entry so one bad reducer doesn't abort
    /// the survey (matching the algebraic survey's error tolerance).
    private static func surveyOne(
        suggestion: InteractionInvariantSuggestion,
        context: RunContext
    ) -> Entry {
        do {
            let result = try VerifyInteractionPipeline.runWithInvariant(
                target: context.target,
                invariant: suggestion,
                sequenceCount: context.sequenceCount,
                userModuleName: context.userModuleName,
                persistEvidence: false,
                workingDirectory: context.workingDirectory
            )
            return Entry(suggestion: suggestion, result: result)
        } catch {
            return Entry(
                suggestion: suggestion,
                result: InteractionVerifyOutcomeParser.Result(
                    outcome: .measuredError,
                    detail: "verify failed: \(error)"
                )
            )
        }
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
