import ArgumentParser
import Foundation
import SwiftInferCore

/// V1.110 (cycle-103d) — `swift-infer accept-bridge` subcommand.
/// Records a decision against a specific `BridgeSuggestion` identity
/// hash in `.swiftinfer/interaction-decisions.json`. Minimal
/// recorder — sibling of v1.88's `accept-interaction` (which is
/// keyed on individual `InteractionInvariantSuggestion` identities).
///
/// **Why a thin gesture.** The bridge-level interactive triage UI
/// (cycle 103b/c, `swift-infer discover-interaction
/// --interactive-bridges`) handles the user-driven case. This
/// subcommand exists for scripted workflows (CI, accept-by-hash
/// from a known identity) without invoking the interactive loop.
///
/// **Decision arms.** Only `acceptedAsConformance` and `rejected`
/// are valid — bridges imply kit-side protocol conformance
/// commitment (PRD §9.4 framing; matches the cycle-103b design
/// decision in `InteractionBridgeInteractiveTriage.applyChoice`).
/// Plain `accepted` and `skipped` are rejected at parse time.
///
/// **`--peer N` scoping.** Optional, 1-based; when present scopes
/// the decision to that peer's invariants only. Omitting `--peer`
/// applies the decision to every peer's invariants in the bridge
/// (matching the `.acceptAll` / `.reject` arms of the interactive
/// form).
///
/// **Resolve flow.** Runs `discover-interaction.collectSuggestions`
/// against the target, computes Strong-tier bridges via
/// `InteractionInvariantBridge.bridges(from:now:)`, matches the
/// user-supplied identity hash against the bridges, then upserts
/// records per the scoping rule. The bridge must be currently
/// discoverable — accepting a hash that no longer corresponds to
/// a live bridge errors out with `unknownBridgeIdentity`.
extension SwiftInferCommand {

    public struct AcceptBridge: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "accept-bridge",
            abstract: "Record a decision against a BridgeSuggestion identity "
                + "(`.swiftinfer/interaction-decisions.json`). Scripted "
                + "analog of the `--interactive-bridges` triage loop."
        )

        @Option(
            name: .long,
            help: "Name of the SwiftPM target. Mirrors `discover-interaction`."
        )
        public var target: String

        @Option(
            name: .long,
            help: """
            16-char uppercase hex identity hash of the BridgeSuggestion. \
            Find via `discover-interaction --interactive-bridges`.
            """
        )
        public var identity: String

        @Option(
            name: .long,
            help: """
            Decision to record: `accepted-as-conformance` or `rejected`. \
            Plain `accepted` / `skipped` are NOT valid for bridges \
            (bridges imply protocol conformance commitment per PRD §9.4).
            """
        )
        public var decision: String

        @Option(
            name: .long,
            help: """
            Optional 1-based peer index. When present, scopes the decision \
            to that peer's invariants only. When omitted, applies the \
            decision to every peer's invariants in the bridge.
            """
        )
        public var peer: Int?

        @Option(
            name: .long,
            help: """
            Optional path to `.swiftinfer/interaction-decisions.json`. When \
            omitted, walks up from the target directory to find Package.swift.
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
                request: AcceptBridgeRequest(
                    identity: identity,
                    decisionRaw: decision,
                    peerIndex: peer,
                    explicitDecisionsPath: decisions.map { URL(fileURLWithPath: $0) }
                ),
                output: PrintOutput(),
                diagnostics: PrintDiagnosticOutput()
            )
        }

        /// V1.110 — full pipeline entry. Loads + parses decision
        /// string → runs `collectSuggestions` + `bridges` → delegates
        /// to `runWithBridges`. The bridge-derivation step is
        /// gated on Strong tier in production (calibration-blocked
        /// until a family promotes), so for testing the `runWithBridges`
        /// seam below accepts an injected bridge list directly.
        public static func run(
            target: String,
            workingDirectory: URL,
            directory: URL,
            request: AcceptBridgeRequest,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput = PrintDiagnosticOutput(),
            now: Date = Date()
        ) throws {
            let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
                target: target,
                workingDirectory: workingDirectory
            )
            let bridges = InteractionInvariantBridge.bridges(from: suggestions, now: now)
            try runWithBridges(
                bridges: bridges,
                directory: directory,
                request: request,
                output: output,
                diagnostics: diagnostics,
                now: now
            )
        }

        /// V1.110 — pure logic seam. Tests inject synthetic Strong-
        /// tier `BridgeSuggestion`s directly (the v1.86 + v1.108
        /// pattern: PRD §3.5's tier-promotion rule keeps every
        /// family at default-`.possible` until calibration unlocks,
        /// so no bridges fire from real source today). Loads
        /// existing decisions, matches the identity, upserts per-
        /// invariant records, writes JSON.
        public static func runWithBridges(
            bridges: [BridgeSuggestion],
            directory: URL,
            request: AcceptBridgeRequest,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput = PrintDiagnosticOutput(),
            now: Date = Date()
        ) throws {
            let decision = try parseDecision(request.decisionRaw)
            let normalizedHash = request.identity.uppercased()
            guard let matched = bridges.first(where: {
                $0.identity.normalized == normalizedHash
            }) else {
                throw AcceptBridgeError.unknownBridgeIdentity(hash: request.identity)
            }
            let invariantsToRecord = try resolveScope(
                bridge: matched,
                peerIndex: request.peerIndex
            )
            let decisionsResult = InteractionDecisionsLoader.load(
                startingFrom: directory,
                explicitPath: request.explicitDecisionsPath
            )
            for warning in decisionsResult.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            var updated = decisionsResult.decisions
            for invariant in invariantsToRecord {
                updated = updated.upserting(InteractionDecisionRecord(
                    identityHash: invariant.identity.normalized,
                    family: invariant.family,
                    scoreAtDecision: invariant.score,
                    tier: invariant.tier,
                    reducerQualifiedName: invariant.reducerQualifiedName,
                    decision: decision,
                    timestamp: now
                ))
            }
            let packageRoot = decisionsResult.packageRoot ?? directory
            let path = request.explicitDecisionsPath
                ?? InteractionDecisionsLoader.defaultPath(for: packageRoot)
            try InteractionDecisionsLoader.write(updated, to: path)
            output.write(renderSummary(
                decision: decision,
                bridge: matched,
                peerIndex: request.peerIndex,
                recordedCount: invariantsToRecord.count
            ))
        }

        /// V1.110 — accept only the two bridge-valid decision values.
        /// `accepted` / `skipped` are explicitly rejected (bridge
        /// semantics imply conformance commitment per PRD §9.4).
        static func parseDecision(_ raw: String) throws -> InteractionDecision {
            guard let decision = InteractionDecision(rawValue: raw) else {
                throw AcceptBridgeError.unknownDecision(raw: raw)
            }
            switch decision {
            case .acceptedAsConformance, .rejected: return decision
            case .accepted, .skipped:
                throw AcceptBridgeError.nonBridgeDecision(raw: raw)
            }
        }

        /// V1.110 — resolve `--peer N` against the bridge's peer
        /// list. When peerIndex is nil, returns every invariant in
        /// every peer. When peerIndex is set, returns the indexed
        /// peer's invariants only; errors if out of range.
        static func resolveScope(
            bridge: BridgeSuggestion,
            peerIndex: Int?
        ) throws -> [InteractionInvariantSuggestion] {
            guard let peerIndex else {
                return bridge.peers.flatMap(\.invariants)
            }
            guard peerIndex >= 1, peerIndex <= bridge.peers.count else {
                throw AcceptBridgeError.peerOutOfRange(
                    index: peerIndex,
                    peerCount: bridge.peers.count
                )
            }
            return bridge.peers[peerIndex - 1].invariants
        }

        /// V1.110 — render the success summary line. Pulled out so
        /// the `run` orchestrator stays under SwiftLint's body cap.
        static func renderSummary(
            decision: InteractionDecision,
            bridge: BridgeSuggestion,
            peerIndex: Int?,
            recordedCount: Int
        ) -> String {
            let scopeText: String
            if let peerIndex {
                let peer = bridge.peers[peerIndex - 1]
                scopeText = "peer #\(peerIndex) (\(peer.kitProtocolName))"
            } else {
                scopeText = "all \(bridge.peers.count) peers"
            }
            return "Recorded \(decision.rawValue) for \(scopeText) of bridge "
                + "0x\(bridge.identity.normalized) on \(bridge.reducerQualifiedName) "
                + "(\(recordedCount) invariants)."
        }
    }
}

/// V1.110 — request bundle for `accept-bridge`. Wraps the "what to
/// record" inputs so the static-pipeline entry stays under
/// SwiftLint's `function_parameter_count` cap. File-scope for the
/// nesting rule.
public struct AcceptBridgeRequest: Sendable {
    public let identity: String
    public let decisionRaw: String
    public let peerIndex: Int?
    public let explicitDecisionsPath: URL?

    public init(
        identity: String,
        decisionRaw: String,
        peerIndex: Int? = nil,
        explicitDecisionsPath: URL? = nil
    ) {
        self.identity = identity
        self.decisionRaw = decisionRaw
        self.peerIndex = peerIndex
        self.explicitDecisionsPath = explicitDecisionsPath
    }
}

/// V1.110 — errors thrown by `accept-bridge`. File-scope for
/// SwiftLint nesting; public so tests pattern-match on cases.
public enum AcceptBridgeError: Error, CustomStringConvertible, Equatable {
    case unknownDecision(raw: String)
    case nonBridgeDecision(raw: String)
    case unknownBridgeIdentity(hash: String)
    case peerOutOfRange(index: Int, peerCount: Int)

    public var description: String {
        switch self {
        case let .unknownDecision(raw):
            return "swift-infer accept-bridge: unknown decision '\(raw)'. "
                + "Valid for bridges: accepted-as-conformance, rejected."
        case let .nonBridgeDecision(raw):
            return "swift-infer accept-bridge: decision '\(raw)' is not valid "
                + "for bridges. Bridges imply kit-side protocol conformance "
                + "commitment (PRD §9.4) — only accepted-as-conformance and "
                + "rejected are accepted."
        case let .unknownBridgeIdentity(hash):
            return "swift-infer accept-bridge: no current bridge matches "
                + "identity 0x\(hash). Re-run discover-interaction "
                + "--interactive-bridges to see the current bridge set."
        case let .peerOutOfRange(index, peerCount):
            return "swift-infer accept-bridge: --peer \(index) out of range "
                + "(bridge has \(peerCount) peers, valid indices 1...\(peerCount))."
        }
    }
}
