import ArgumentParser
import Foundation
import SwiftInferCore

/// V1.72.A — `swift-infer accept-check` subcommand surface.
///
/// **What it does.** Walks `.swiftinfer/decisions.json`, filters to
/// `accepted` + `acceptedAsConformance` records, and re-runs the
/// `verify` pipeline against each suggestion's current state in source.
/// The four-state classification per suggestion answers PRD §17.2's 5th
/// metric question — "did the property the user accepted still hold
/// after the function evolved?":
///
///   - `stillPasses` — re-verify returned `bothPass` or
///     `edgeCaseAdvisory`. No regression.
///   - `nowFails` — re-verify returned `defaultFails`. The accepted
///     property is now disproven (the function changed in a
///     property-violating way — the signal §17.2 is really after).
///   - `obsolete` — the accepted suggestion's identity hash no longer
///     surfaces in the current SemanticIndex (function renamed /
///     removed / evolved past the suggestion shape). Informative;
///     not a failure.
///   - `error` — re-verify could not produce a verdict (build failure,
///     unsupported template/carrier/pair, runtime error, or
///     architectural-pending). Not measurable on this run.
///
/// **V1.72.A scope.** Subcommand surface + classification + summary
/// render only. The post-acceptance-outcomes.json persistence ships in
/// V1.72.B; the §17.2 post-acceptance failure-rate section ships in
/// V1.72.C. This phase is "the gesture works and prints" — running
/// `swift-infer accept-check` on a real corpus produces a readable
/// summary but the result is not yet a metric on disk.
///
/// **Opt-in posture.** Same as `verify`: a separate human gesture
/// from `discover` / `drift` / `accept`. Nothing else changes.
extension SwiftInferCommand {

    public struct AcceptCheck: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "accept-check",
            abstract: "Re-run the verify gesture for each accepted "
                + "suggestion in `.swiftinfer/decisions.json` and report "
                + "which previously-accepted properties still hold "
                + "(PRD §17.2 5th metric — regression detection). "
                + "Opt-in / human-driven; mirrors the `verify` posture."
        )

        @Option(
            name: .long,
            help: """
            Path to `.swiftinfer/decisions.json`. When omitted, \
            swift-infer walks up from the working directory to find \
            Package.swift, then reads \
            <package-root>/.swiftinfer/decisions.json (mirrors \
            `metrics` / `discover` / `drift`).
            """
        )
        public var decisions: String?

        @Option(
            name: .long,
            help: """
            Optional template-name filter. Only re-check accepted \
            decisions whose `template` matches. Useful for cycling \
            through one template at a time without re-running the \
            full accepted-decision walk.
            """
        )
        public var template: String?

        @Option(
            name: .long,
            help: """
            Trial budget passed to each verify re-run. Same vocabulary \
            as `verify --budget`: `small` (N=100, the default for an \
            opt-in gesture) or `standard` (N=1000, higher confidence \
            at ~30-60s per call). Unknown values fall back to `small` \
            with a diagnostic.
            """
        )
        public var budget: String = "small"

        @Option(
            name: .long,
            help: """
            Path to a specific SemanticIndex file, forwarded to each \
            verify call. When omitted, verify resolves the conventional \
            <package-root>/.swiftinfer/index.json (reindexing on demand \
            if missing / stale, V1.42.C.5).
            """
        )
        public var indexPath: String?

        public init() {}

        public func run() async {
            let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let rendered = Self.runPipeline(
                decisionsPathOverride: decisions,
                templateFilter: template,
                budgetString: budget,
                indexPathOverride: indexPath,
                workingDirectory: workingDirectory
            )
            print(rendered, terminator: "")
        }

        /// V1.72.A — pure-ish pipeline entry. Tests drive it without
        /// going through the AsyncParsableCommand shell. Returns the
        /// rendered summary string; the CLI's `run()` just prints it.
        ///
        /// Pipeline steps in order:
        ///   1. Load `decisions.json` (default walk-up or explicit
        ///      `--decisions` path).
        ///   2. Filter to `accepted` + `acceptedAsConformance` records,
        ///      optionally narrowed by `--template`.
        ///   3. For each, call `Verify.runPipeline` and classify the
        ///      result into a `PostAcceptanceOutcomeKind`. Verify
        ///      errors that mean "function evolved past the
        ///      suggestion" classify as `.obsolete`; other verify
        ///      errors classify as `.error`.
        ///   4. Render the per-record table + a per-kind summary.
        static func runPipeline(
            decisionsPathOverride: String?,
            templateFilter: String?,
            budgetString: String,
            indexPathOverride: String?,
            workingDirectory: URL
        ) -> String {
            let loaded = DecisionsLoader.load(
                startingFrom: workingDirectory,
                explicitPath: decisionsPathOverride.map { URL(fileURLWithPath: $0) }
            )
            for warning in loaded.warnings {
                FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
            }
            let candidates = acceptedRecords(
                from: loaded.decisions,
                templateFilter: templateFilter
            )
            let packageRoot = loaded.packageRoot ?? workingDirectory
            var results: [AcceptCheckResult] = []
            for record in candidates {
                let outcome = checkOne(
                    record: record,
                    budgetString: budgetString,
                    indexPathOverride: indexPathOverride,
                    workingDirectory: workingDirectory
                )
                // V1.72.B — persist after each check. Per-record write
                // mirrors `VerifyEvidenceRecorder.record(_:)`: a process
                // crash mid-run leaves prior verdicts on disk for the
                // §17.2 join to consume. Best-effort: warnings surface
                // on stderr but never abort the run.
                let warnings = persist(
                    record: record,
                    outcome: outcome,
                    packageRoot: packageRoot
                )
                for warning in warnings {
                    FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
                }
                results.append(
                    AcceptCheckResult(record: record, kind: outcome.kind, detail: outcome.detail)
                )
            }
            return renderSummary(results: results)
        }

        /// V1.72.B — build a `PostAcceptanceOutcome` from the
        /// decision + classified verdict and upsert it into
        /// `post-acceptance-outcomes.json` under `packageRoot`. Best-
        /// effort: read warnings + any write failure are returned for
        /// the caller to surface on stderr — accept-check never fails
        /// on a persistence error (same posture as
        /// `VerifyEvidenceRecorder.record(_:)`).
        static func persist(
            record: DecisionRecord,
            outcome: (kind: PostAcceptanceOutcomeKind, detail: String?),
            packageRoot: URL,
            now: Date = Date()
        ) -> [String] {
            let existing = PostAcceptanceOutcomesStore.load(startingFrom: packageRoot)
            var warnings = existing.warnings
            let path = PostAcceptanceOutcomesStore.defaultPath(for: packageRoot)
            let persisted = PostAcceptanceOutcome(
                identityHash: record.identityHash,
                template: record.template,
                outcome: outcome.kind,
                detail: outcome.detail,
                originalAcceptedAt: record.timestamp,
                checkedAt: now,
                swiftInferVersion: SwiftInferCommand.configuration.version
            )
            do {
                try PostAcceptanceOutcomesStore.write(
                    existing.log.upserting(persisted),
                    to: path
                )
            } catch {
                warnings.append(
                    "could not write post-acceptance-outcomes to \(path.path): "
                        + error.localizedDescription
                )
            }
            return warnings
        }

        /// Filter the loaded decisions to acceptances and apply the
        /// optional template-name filter. Pure — exposed at the type
        /// level so unit tests don't need a fixture decisions.json.
        static func acceptedRecords(
            from decisions: Decisions,
            templateFilter: String?
        ) -> [DecisionRecord] {
            decisions.records.filter { record in
                switch record.decision {
                case .accepted, .acceptedAsConformance:
                    break

                case .rejected, .skipped:
                    return false
                }
                if let templateFilter, record.template != templateFilter {
                    return false
                }
                return true
            }
        }

        /// Drive one verify re-run + classify the outcome. Errors
        /// surface as a `(kind, detail)` pair rather than throwing —
        /// the gesture must keep iterating past one bad record.
        ///
        /// Reads `verify-evidence.json` after the call to pick up the
        /// freshly-written verdict (the verify pipeline upserts there
        /// on success). The just-written record's `outcome` maps
        /// directly through `classify(evidence:)`.
        static func checkOne(
            record: DecisionRecord,
            budgetString: String,
            indexPathOverride: String?,
            workingDirectory: URL
        ) -> (kind: PostAcceptanceOutcomeKind, detail: String?) {
            do {
                _ = try Verify.runPipeline(
                    suggestionPrefix: record.identityHash,
                    indexPathOverride: indexPathOverride,
                    budgetString: budgetString,
                    workingDirectory: workingDirectory
                )
                let evidence = VerifyEvidenceStore.load(startingFrom: workingDirectory)
                guard let post = evidence.log.record(for: record.identityHash) else {
                    return (.error, "verify-evidence missing after re-run")
                }
                return classify(evidence: post.outcome)
            } catch VerifyError.suggestionNotFound {
                return (.obsolete, "identity hash no longer surfaces in current source")
            } catch let VerifyError.unsupportedTemplate(template, _) {
                return (.error, "unsupported template '\(template)'")
            } catch let VerifyError.unsupportedCarrier(carrier, _) {
                return (.error, "unsupported carrier '\(carrier)'")
            } catch let VerifyError.unsupportedPair(forward, _) {
                return (.error, "unsupported pair forward '\(forward)'")
            } catch let VerifyError.buildFailed(exitCode, _) {
                return (.error, "build failed (exit \(exitCode))")
            } catch VerifyError.runnerCrashed {
                return (.error, "verifier runner crashed")
            } catch VerifyError.indexMissing, VerifyError.indexEmpty {
                return (.error, "SemanticIndex missing or empty")
            } catch VerifyError.ambiguousPrefix {
                return (.error, "identity hash matched multiple index entries")
            } catch {
                return (.error, "\(error)")
            }
        }

        /// V1.72.A — coarse-grained classification: five
        /// `VerifyEvidenceOutcome` states collapse into the four-state
        /// `PostAcceptanceOutcomeKind` vocabulary. Pure.
        ///
        /// - `measuredBothPass` and `measuredEdgeCaseAdvisory` both
        ///   mean "the property holds" → `.stillPasses`. The advisory
        ///   sub-state distinction matters at verify time (the user
        ///   wants to see curated edge cases on first pass) but not
        ///   here — for post-acceptance we only care whether the
        ///   accepted property survived.
        /// - `measuredDefaultFails` → `.nowFails`. Regression.
        /// - `measuredError` and `architecturalCoveragePending` both
        ///   mean "could not measure" → `.error`. The architectural
        ///   sub-state isn't a verdict either way.
        static func classify(
            evidence: VerifyEvidenceOutcome
        ) -> (kind: PostAcceptanceOutcomeKind, detail: String?) {
            switch evidence {
            case .measuredBothPass:
                return (.stillPasses, "bothPass")

            case .measuredEdgeCaseAdvisory:
                return (.stillPasses, "edgeCaseAdvisory")

            case .measuredDefaultFails:
                return (.nowFails, "defaultFails")

            case .measuredError:
                return (.error, "verify-error")

            case .architecturalCoveragePending:
                return (.error, "architectural-coverage-pending")
            }
        }

        /// V1.72.A — summary text emitted to stdout. One line per
        /// re-checked decision plus a per-kind tally. Byte-stable for
        /// tests: identity-hash ordering preserves the input
        /// decision-record order so a deterministic fixture decisions
        /// file produces a deterministic summary.
        static func renderSummary(results: [AcceptCheckResult]) -> String {
            if results.isEmpty {
                return "swift-infer accept-check: no accepted decisions to re-check.\n"
            }
            var lines: [String] = []
            let suffix = results.count == 1 ? "" : "s"
            lines.append(
                "swift-infer accept-check — re-verified \(results.count) accepted decision\(suffix):"
            )
            lines.append("")
            for result in results {
                let detail = result.detail.map { " (\($0))" } ?? ""
                lines.append(
                    "  \(result.record.identityHash)  \(result.record.template)  "
                        + "\(result.kind.rawValue)\(detail)"
                )
            }
            lines.append("")
            var counts: [PostAcceptanceOutcomeKind: Int] = [:]
            for result in results {
                counts[result.kind, default: 0] += 1
            }
            lines.append("Summary:")
            for kind in PostAcceptanceOutcomeKind.allCases {
                lines.append("  \(kind.rawValue): \(counts[kind] ?? 0)")
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }
}

/// V1.72.A — per-decision accept-check result. File-scope rather than
/// nested under `SwiftInferCommand.AcceptCheck` to satisfy SwiftLint's
/// 1-level `nesting` cap — `AcceptCheck` is already nested inside
/// `SwiftInferCommand` via the extension, so a third level here would
/// violate the rule. Mirrors how `VerifyError` is hoisted out of
/// `SwiftInferCommand.Verify` for the same reason.
public struct AcceptCheckResult: Equatable {
    public let record: DecisionRecord
    public let kind: PostAcceptanceOutcomeKind
    public let detail: String?

    public init(
        record: DecisionRecord,
        kind: PostAcceptanceOutcomeKind,
        detail: String?
    ) {
        self.record = record
        self.kind = kind
        self.detail = detail
    }
}
