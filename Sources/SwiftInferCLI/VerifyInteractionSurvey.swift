import Foundation
import SwiftInferCore

/// Cycle 114 — the `verify-interaction --all` survey: discover every
/// interaction-invariant identity in a target, run measured verify against
/// each, record evidence, and render a per-identity outcome summary. This
/// is the campaign's "harvest" step — one command instead of N hand-pinned
/// `verify-interaction` runs — feeding `verify-evidence.json` so a later
/// `discover-interaction` surfaces the survivors at `.verified`.
///
/// **Reducer-grouped bounded-parallel (cycle 120).** Up to `maxParallel`
/// *reducer groups* build concurrently (`withTaskGroup`, drain-and-refill
/// like the algebraic `--all-from-index` survey); a group's sibling
/// identities run serially in one shared reducer-keyed workdir so the 2nd+
/// rebuilds only the changed stub (warm `.build/` reuse — the speedup
/// lever m4 added after the m1–m3 per-invariant fan-out showed no
/// wall-clock gain). Safe + deterministic via: distinct groups touch
/// distinct workdirs (no concurrent clobber); m2's `persistEvidence: false`
/// + single batch write (no lost records); and a re-sort to discovery
/// order (stable output despite nondeterministic completion). Each task
/// is real `swift build`s, so the cap is conservative (default 4).
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
        /// M3 — the surveyed targets (modules). One for a single-module run;
        /// several when the survey spans modules. Each identity is verified
        /// against *its own* module (`suggestion.moduleName`), falling back to
        /// the first target when untagged (single-module runs don't tag).
        let targets: [String]
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
    /// Single-target convenience — delegates to the multi-target form.
    static func run(
        target: String,
        familyFilter: String?,
        sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
        userModuleName: String? = nil,
        maxParallel: Int = 4,
        workingDirectory: URL
    ) async throws -> String {
        try await run(
            targets: [target],
            familyFilter: familyFilter,
            sequenceCount: sequenceCount,
            userModuleName: userModuleName,
            maxParallel: maxParallel,
            workingDirectory: workingDirectory
        )
    }

    /// M3 — multi-target survey. Discovers across every `--target` (module),
    /// tagging each identity with its module, and verifies each against *its*
    /// module's library product — so reducers from different modules are
    /// measured in one run. Single-target is the `targets == [x]` case
    /// (identities untagged; verified against `x` as before).
    static func run(
        targets: [String],
        familyFilter: String?,
        sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
        userModuleName: String? = nil,
        maxParallel: Int = 4,
        workingDirectory: URL
    ) async throws -> String {
        let all = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            targets: targets,
            workingDirectory: workingDirectory
        )
        let family = try parseFamily(familyFilter)
        let selected = family.map { chosen in all.filter { $0.family == chosen } } ?? all
        let display = targets.joined(separator: ", ")

        guard !selected.isEmpty else {
            return render(target: display, family: family, entries: [])
        }

        let context = RunContext(
            targets: targets,
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
        return render(target: display, family: family, entries: entries)
    }

    /// One identity tagged with its discovery position, so completion in
    /// any order can be re-sorted back to a deterministic render order.
    private typealias IndexedSuggestion = (index: Int, suggestion: InteractionInvariantSuggestion)

    /// Cycle 120 m4 — reducer-grouped bounded-parallel fan-out. The unit
    /// of parallelism is a *reducer group*, not a single identity: groups
    /// run concurrently (bounded by `parallelism`, drain-and-refill like
    /// the algebraic survey), but a group's identities run serially in one
    /// shared reducer-keyed workdir. That keeps the warm-`.build/` reuse
    /// the old serial path had (sibling identities rebuild only the changed
    /// stub) while still parallelizing distinct reducers. Distinct groups
    /// touch distinct workdirs, so no concurrent build clobbers another.
    /// Results carry their discovery index and are re-sorted before return,
    /// so the summary + batch-record order stay deterministic.
    private static func runSurvey(
        selected: [InteractionInvariantSuggestion],
        context: RunContext,
        parallelism: Int
    ) async -> [Entry] {
        let groups = groupByReducer(selected)
        var collected: [(index: Int, entry: Entry)] = []
        await withTaskGroup(of: [(index: Int, entry: Entry)].self) { group in
            var inFlight = 0
            var nextGroup = 0
            func submitNext() {
                let items = groups[nextGroup]
                nextGroup += 1
                inFlight += 1
                group.addTask {
                    items.map { ($0.index, surveyOne(suggestion: $0.suggestion, context: context)) }
                }
            }
            while nextGroup < groups.count, inFlight < parallelism { submitNext() }
            while let done = await group.next() {
                inFlight -= 1
                collected.append(contentsOf: done)
                if nextGroup < groups.count { submitNext() }
            }
        }
        return collected.sorted { $0.index < $1.index }.map(\.entry)
    }

    /// Partition identities by reducer, preserving first-appearance order
    /// for both the groups and the identities within each — so the survey
    /// is deterministic and the re-sort restores exact discovery order.
    private static func groupByReducer(
        _ selected: [InteractionInvariantSuggestion]
    ) -> [[IndexedSuggestion]] {
        var order: [String] = []
        var byReducer: [String: [IndexedSuggestion]] = [:]
        for (index, suggestion) in selected.enumerated() {
            // M3 — key includes the module so same-named reducers in different
            // modules form distinct groups (distinct workdirs), not one shared.
            let key = (suggestion.moduleName ?? "") + "|" + suggestion.reducerQualifiedName
            if byReducer[key] == nil { order.append(key) }
            byReducer[key, default: []].append((index, suggestion))
        }
        return order.map { byReducer[$0]! }
    }

    /// Per-identity worker. Runs the full measured verify; maps any thrown
    /// error to a `.measuredError` entry so one bad reducer doesn't abort
    /// the survey (matching the algebraic survey's error tolerance).
    private static func surveyOne(
        suggestion: InteractionInvariantSuggestion,
        context: RunContext
    ) -> Entry {
        do {
            // M3 — verify against this identity's own module: the module is
            // both the `Sources/<module>/` discovery dir and the library
            // product. Untagged (single-module) → the first target, preserving
            // the pre-M3 behavior exactly.
            let verifyTarget = suggestion.moduleName ?? context.targets.first ?? ""
            let result = try VerifyInteractionPipeline.runWithInvariant(
                target: verifyTarget,
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
