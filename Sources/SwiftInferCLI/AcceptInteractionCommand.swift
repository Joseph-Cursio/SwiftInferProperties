import ArgumentParser
import Foundation
import SwiftInferCore

/// V2.0 — `swift-infer accept-interaction` subcommand. Records a
/// decision against a specific interaction-invariant identity hash
/// in `.swiftinfer/interaction-decisions.json`. Minimal recorder —
/// no interactive triage UI (that's a separate follow-up, the
/// N-arm prompt for M9's peer proposals).
///
/// **Why a thin gesture.** The interactive triage path is a
/// substantial UI piece (PRD §9.4's `[A/B/B'/B''/.../s/n/?]`); this
/// subcommand exists so users + tests can record decisions today
/// without the UI. Once interactive triage lands, it'll write the
/// same decisions JSON via the same loader.
///
/// **Resolve flow.** Runs `discover-interaction` against the target
/// to enumerate current suggestions, matches the user-supplied
/// identity hash against the result, then upserts a record. The
/// suggestion must be currently discoverable — accepting a hash
/// that no longer corresponds to a live suggestion errors out
/// with `unknownIdentity` (clear failure beats silent acceptance).
extension SwiftInferCommand {

    public struct AcceptInteraction: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "accept-interaction",
            abstract: "Record a decision against an interaction-invariant "
                + "suggestion identity (`.swiftinfer/interaction-decisions.json`). "
                + "Minimal recorder — the interactive triage UI is "
                + "a separate follow-up."
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
            16-char uppercase hex identity hash of the suggestion to \
            record a decision against. Find this via `discover-interaction`.
            """
        )
        public var identity: String

        @Option(
            name: .long,
            help: """
            Decision to record: `accepted`, `accepted-as-conformance`, \
            `rejected`, or `skipped`. Matches `InteractionDecision`'s \
            rawValues.
            """
        )
        public var decision: String

        @Option(
            name: .long,
            help: """
            Optional path to `.swiftinfer/interaction-decisions.json`. \
            When omitted, walks up from the target directory to find \
            Package.swift.
            """
        )
        public var decisions: String?

        public init() { /* no-op */ }

        public func run() async throws {
            let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
            try Self.run(
                target: target,
                workingDirectory: workingDirectory,
                directory: directory,
                request: AcceptInteractionRequest(
                    identity: identity,
                    decisionRaw: decision,
                    explicitDecisionsPath: decisions.map { URL(fileURLWithPath: $0) }
                ),
                output: PrintOutput(),
                diagnostics: PrintDiagnosticOutput()
            )
        }

        /// V2.0 — pure pipeline. Tests drive it without going through
        /// ArgumentParser. Loads + parses decision string → runs
        /// `discover-interaction.collectSuggestions` → matches identity
        /// → upserts the record → writes the decisions JSON.
        public static func run(
            target: String,
            workingDirectory: URL,
            directory: URL,
            request: AcceptInteractionRequest,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput = PrintDiagnosticOutput(),
            now: Date = Date()
        ) throws {
            guard let decision = InteractionDecision(rawValue: request.decisionRaw) else {
                throw AcceptInteractionError.unknownDecision(raw: request.decisionRaw)
            }
            let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
                target: target,
                workingDirectory: workingDirectory
            )
            let normalizedHash = request.identity.uppercased()
            guard let matched = suggestions.first(where: {
                $0.identity.normalized == normalizedHash
            }) else {
                throw AcceptInteractionError.unknownIdentity(hash: request.identity)
            }
            let decisionsResult = InteractionDecisionsLoader.load(
                startingFrom: directory,
                explicitPath: request.explicitDecisionsPath
            )
            for warning in decisionsResult.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            let record = InteractionDecisionRecord(
                identityHash: matched.identity.normalized,
                family: matched.family,
                scoreAtDecision: matched.score,
                tier: matched.tier,
                reducerQualifiedName: matched.reducerQualifiedName,
                decision: decision,
                timestamp: now
            )
            let updated = decisionsResult.decisions.upserting(record)
            let packageRoot = decisionsResult.packageRoot ?? directory
            let path = request.explicitDecisionsPath
                ?? InteractionDecisionsLoader.defaultPath(for: packageRoot)
            try InteractionDecisionsLoader.write(updated, to: path)
            output.write(
                "Recorded \(decision.rawValue) for \(matched.family.rawValue) invariant "
                    + "0x\(matched.identity.normalized) on \(matched.reducerQualifiedName)."
            )
        }
    }
}

/// V2.0 — request bundle for `accept-interaction`. Wraps the
/// "what to record" inputs so the static-pipeline entry stays
/// under SwiftLint's `function_parameter_count` cap. File-scope for
/// the `nesting` rule (the owning subcommand is already nested
/// inside `SwiftInferCommand` via extension).
public struct AcceptInteractionRequest: Sendable {
    public let identity: String
    public let decisionRaw: String
    public let explicitDecisionsPath: URL?

    public init(
        identity: String,
        decisionRaw: String,
        explicitDecisionsPath: URL? = nil
    ) {
        self.identity = identity
        self.decisionRaw = decisionRaw
        self.explicitDecisionsPath = explicitDecisionsPath
    }
}

/// V2.0 — errors thrown by `accept-interaction`. File-scope for
/// SwiftLint nesting; public so tests pattern-match on cases.
public enum AcceptInteractionError: Error, CustomStringConvertible, Equatable {
    case unknownDecision(raw: String)
    case unknownIdentity(hash: String)

    public var description: String {
        switch self {
        case let .unknownDecision(raw):
            return "swift-infer accept-interaction: unknown decision '\(raw)'. "
                + "Valid: accepted, accepted-as-conformance, rejected, skipped."

        case let .unknownIdentity(hash):
            return "swift-infer accept-interaction: no current suggestion "
                + "matches identity 0x\(hash). Re-run discover-interaction "
                + "to see the current set."
        }
    }
}
