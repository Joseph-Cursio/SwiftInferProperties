import ArgumentParser
import Foundation
import SwiftInferCore

/// V2.0 accept-check follow-up — `swift-infer accept-check-interaction`
/// subcommand. Analog of v1.72.A's `accept-check` but keyed on
/// interaction invariants. Walks
/// `.swiftinfer/interaction-decisions.json`, filters to
/// `.accepted` + `.acceptedAsConformance`, re-runs `verify-interaction`
/// against each suggestion's current source state, and classifies
/// outcomes per `InteractionPostAcceptanceOutcomeKind`.
///
/// **Four-state classification.**
///   - `stillPasses` — re-verify produced `.measuredBothPass`.
///   - `nowFails` — re-verify produced `.measuredDefaultFails`. The
///     accepted invariant is now disproven; this is the regression
///     signal the metric is after.
///   - `obsolete` — the accepted suggestion's identity hash no
///     longer surfaces in current `discover-interaction` output
///     (reducer renamed / removed / family-witness shape evolved).
///   - `error` — re-verify produced
///     `.measuredError` / `.architecturalCoveragePending` (build
///     failure, unsupported shape/carrier, etc.).
///
/// **Persistence.** Outcomes write to
/// `.swiftinfer/interaction-post-acceptance-outcomes.json` via the
/// `InteractionPostAcceptanceOutcomesStore`. Upsert by identity; the
/// latest re-run wins.
///
/// **Opt-in posture.** Mirrors `verify-interaction` and v1's
/// `accept-check` — a separate human gesture, not run automatically
/// by `discover-interaction` / `drift-interaction`.
extension SwiftInferCommand {

    public struct AcceptCheckInteraction: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "accept-check-interaction",
            abstract: "Re-run verify-interaction for each accepted "
                + "decision in .swiftinfer/interaction-decisions.json "
                + "and report which previously-accepted invariants "
                + "still hold (PRD §17.2 5th metric — interaction "
                + "analog). Opt-in / human-driven."
        )

        @Option(
            name: .long,
            help: """
            Name of the SwiftPM target. Mirrors `discover-interaction`.
            """
        )
        public var target: String

        @Option(
            name: .long,
            help: """
            Optional family-name filter (`conservation`, \
            `idempotence`, `cardinality`, `referential-integrity`, \
            `biconditional`). Restricts the rerun to one family at \
            a time.
            """
        )
        public var family: String?

        @Option(
            name: .long,
            help: """
            Path to `.swiftinfer/interaction-decisions.json`. When \
            omitted, walks up from the target directory to find \
            Package.swift.
            """
        )
        public var decisions: String?

        public init() {}

        public func run() async throws {
            let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
            try Self.run(
                target: target,
                workingDirectory: workingDirectory,
                directory: directory,
                familyFilterRaw: family,
                explicitDecisionsPath: decisions.map { URL(fileURLWithPath: $0) },
                output: PrintOutput(),
                diagnostics: PrintDiagnosticOutput()
            )
        }

        /// V2.0 — pure pipeline. Tests drive it without going through
        /// ArgumentParser. Loads decisions → for each accepted record:
        /// look up the current suggestion → run `verify-interaction`
        /// against it (or mark `.obsolete` if missing) → classify
        /// outcome → upsert into the outcomes log → persist.
        public static func run(
            target: String,
            workingDirectory: URL,
            directory: URL,
            familyFilterRaw: String? = nil,
            explicitDecisionsPath: URL? = nil,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput = PrintDiagnosticOutput(),
            now: Date = Date(),
            swiftInferVersion: String = "swift-infer-development"
        ) throws {
            let familyFilter = try parseFamilyFilter(familyFilterRaw)
            let decisionsResult = InteractionDecisionsLoader.load(
                startingFrom: directory,
                explicitPath: explicitDecisionsPath
            )
            for warning in decisionsResult.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            let byIdentity = try collectCurrentSuggestions(
                target: target,
                workingDirectory: workingDirectory
            )
            let outcomesStore = InteractionPostAcceptanceOutcomesStore.load(
                startingFrom: directory
            )
            for warning in outcomesStore.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            let acceptedRecords = filterAccepted(
                decisionsResult.decisions.records,
                familyFilter: familyFilter
            )
            let updatedLog = runChecks(
                acceptedRecords: acceptedRecords,
                byIdentity: byIdentity,
                existingLog: outcomesStore.log,
                metadata: AcceptCheckInteractionCheckMetadata(
                    target: target,
                    workingDirectory: workingDirectory,
                    now: now,
                    swiftInferVersion: swiftInferVersion
                ),
                output: output
            )
            let packageRoot = decisionsResult.packageRoot ?? directory
            let outcomesPath = InteractionPostAcceptanceOutcomesStore.defaultPath(for: packageRoot)
            try InteractionPostAcceptanceOutcomesStore.write(updatedLog, to: outcomesPath)
            if acceptedRecords.isEmpty {
                output.write("No accepted interaction decisions to check.")
            }
        }

        // MARK: - Loop / classification helpers

        private static func collectCurrentSuggestions(
            target: String,
            workingDirectory: URL
        ) throws -> [String: InteractionInvariantSuggestion] {
            let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
                target: target,
                workingDirectory: workingDirectory
            )
            return Dictionary(
                uniqueKeysWithValues: suggestions.map { ($0.identity.normalized, $0) }
            )
        }

        private static func filterAccepted(
            _ records: [InteractionDecisionRecord],
            familyFilter: InteractionInvariantFamily?
        ) -> [InteractionDecisionRecord] {
            records.filter { record in
                guard record.decision == .accepted
                    || record.decision == .acceptedAsConformance else { return false }
                if let familyFilter, record.family != familyFilter { return false }
                return true
            }
        }

        private static func runChecks(
            acceptedRecords: [InteractionDecisionRecord],
            byIdentity: [String: InteractionInvariantSuggestion],
            existingLog: InteractionPostAcceptanceOutcomeLog,
            metadata: AcceptCheckInteractionCheckMetadata,
            output: any DiscoverOutput
        ) -> InteractionPostAcceptanceOutcomeLog {
            var log = existingLog
            for record in acceptedRecords {
                let outcome = classify(
                    record: record,
                    matching: byIdentity[record.identityHash],
                    target: metadata.target,
                    workingDirectory: metadata.workingDirectory
                )
                let stored = InteractionPostAcceptanceOutcome(
                    identityHash: record.identityHash,
                    family: record.family,
                    outcome: outcome.kind,
                    detail: outcome.detail,
                    originalAcceptedAt: record.timestamp,
                    checkedAt: metadata.now,
                    swiftInferVersion: metadata.swiftInferVersion
                )
                log = log.upserting(stored)
                output.write(renderLine(record: record, outcome: outcome))
            }
            return log
        }

        static func classify(
            record _: InteractionDecisionRecord,
            matching current: InteractionInvariantSuggestion?,
            target: String,
            workingDirectory: URL
        ) -> InteractionAcceptCheckOutcome {
            guard let invariant = current else {
                return InteractionAcceptCheckOutcome(
                    kind: .obsolete,
                    detail: "identity hash no longer surfaces in current source"
                )
            }
            do {
                let result = try VerifyInteractionPipeline.runWithInvariant(
                    target: target,
                    invariant: invariant,
                    workingDirectory: workingDirectory
                )
                return classify(verifyOutcome: result)
            } catch {
                return InteractionAcceptCheckOutcome(
                    kind: .error,
                    detail: "verify-interaction threw: \(error.localizedDescription)"
                )
            }
        }

        static func classify(
            verifyOutcome: InteractionVerifyOutcomeParser.Result
        ) -> InteractionAcceptCheckOutcome {
            switch verifyOutcome.outcome {
            case .measuredBothPass:
                return InteractionAcceptCheckOutcome(kind: .stillPasses, detail: "bothPass")

            case .measuredDefaultFails:
                return InteractionAcceptCheckOutcome(
                    kind: .nowFails,
                    detail: verifyOutcome.detail ?? "defaultFails"
                )

            case .measuredEdgeCaseAdvisory:
                return InteractionAcceptCheckOutcome(
                    kind: .stillPasses,
                    detail: "edgeCaseAdvisory"
                )

            case .measuredError:
                return InteractionAcceptCheckOutcome(
                    kind: .error,
                    detail: verifyOutcome.detail ?? "measuredError"
                )

            case .architecturalCoveragePending:
                return InteractionAcceptCheckOutcome(
                    kind: .error,
                    detail: verifyOutcome.detail ?? "architectural-coverage-pending"
                )
            }
        }

        // MARK: - Family-filter parsing

        private static func parseFamilyFilter(
            _ raw: String?
        ) throws -> InteractionInvariantFamily? {
            guard let raw else { return nil }
            guard let family = InteractionInvariantFamily(rawValue: raw) else {
                throw AcceptCheckInteractionError.unknownFamily(raw: raw)
            }
            return family
        }

        // MARK: - Rendering

        private static func renderLine(
            record: InteractionDecisionRecord,
            outcome: InteractionAcceptCheckOutcome
        ) -> String {
            let detailPart = outcome.detail.map { " — \($0)" } ?? ""
            return "[\(outcome.kind.rawValue)] \(record.family.rawValue) invariant "
                + "0x\(record.identityHash) on \(record.reducerQualifiedName)\(detailPart)"
        }
    }
}

/// V2.0 accept-check follow-up — classified result of one
/// accept-check rerun. File-scope for SwiftLint nesting (the
/// owning subcommand is already nested inside `SwiftInferCommand`
/// via extension). Public so tests pattern-match on the kind /
/// detail fields.
/// V1.89 lint pass — per-check context bundle, lifted from
/// `runChecks`'s 8-param signature so the function stays under the
/// `function_parameter_count` cap. File-scope rather than nested
/// under `AcceptCheckInteraction` to satisfy the 1-level `nesting`
/// rule.
struct AcceptCheckInteractionCheckMetadata {
    let target: String
    let workingDirectory: URL
    let now: Date
    let swiftInferVersion: String
}

public struct InteractionAcceptCheckOutcome: Equatable, Sendable {
    public let kind: InteractionPostAcceptanceOutcomeKind
    public let detail: String?

    public init(kind: InteractionPostAcceptanceOutcomeKind, detail: String?) {
        self.kind = kind
        self.detail = detail
    }
}

/// V2.0 accept-check follow-up — errors thrown by
/// `accept-check-interaction`. File-scope for SwiftLint nesting;
/// public so tests pattern-match on cases.
public enum AcceptCheckInteractionError: Error, CustomStringConvertible, Equatable {
    case unknownFamily(raw: String)

    public var description: String {
        switch self {
        case let .unknownFamily(raw):
            return "swift-infer accept-check-interaction: unknown family "
                + "'\(raw)'. Valid: conservation, idempotence, cardinality, "
                + "referential-integrity, biconditional."
        }
    }
}
