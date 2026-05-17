import Foundation
import SwiftInferCore

/// V1.108 (cycle-103b) — interactive triage loop for M9 Bridge
/// proposals. Walks the user through each `BridgeSuggestion` one at
/// a time, prompts `[A/1/2/.../s/n/?]`, records the chosen
/// `InteractionDecision` per-invariant to
/// `.swiftinfer/interaction-decisions.json`.
///
/// **The N-arm framing (PRD §9.4).** A Bridge bundles ≥ 2 distinct-
/// family peer proposals on the same reducer. The user can:
///   - `a` — accept all peers as conformance (records
///     `acceptedAsConformance` for every invariant in every peer).
///   - `1`, `2`, ... `N` — accept only that peer's invariants
///     (records `acceptedAsConformance` for that peer; other
///     peers' invariants stay undecided, re-surface in future runs).
///   - `s` — skip the whole bridge (no records written).
///   - `n` — reject all peers (records `rejected` for every
///     invariant in every peer).
///   - `?` — show help.
///
/// **Numeric arm labels** vs PRD §9.4's `B/B'/B''` notation:
/// numeric labels scale cleanly to N peers and avoid the
/// apostrophe-typing UX cost. The PRD's notation is a doc-only
/// convention; this CLI uses `1`, `2`, ... for typing convenience.
///
/// **Sibling of v1.98's `InteractionInteractiveTriage`.** Same
/// prompt-loop pattern (`PromptInput` → readLine → switch on
/// choice → record), different data type. v1.98 walks
/// `[InteractionInvariantSuggestion]`; v1.108 walks
/// `[BridgeSuggestion]`. The two suites stay independent because
/// the bridge form has multiple peers per item.
public enum InteractionBridgeInteractiveTriage {

    /// V1.108 — one prompt outcome from `readChoice`.
    public enum Choice: Equatable, Sendable {
        case acceptAll
        case acceptPeer(index: Int)
        case skip
        case reject
    }

    /// V1.108 — input bundle for the bridge-triage session.
    /// Mirrors v1.98's `InteractionInteractiveTriage.Inputs` shape.
    public struct Inputs {
        public let prompt: any PromptInput
        public let output: any DiscoverOutput
        public let diagnostics: any DiagnosticOutput
        public let dryRun: Bool
        public let now: Date

        public init(
            prompt: any PromptInput,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput,
            dryRun: Bool,
            now: Date = Date()
        ) {
            self.prompt = prompt
            self.output = output
            self.diagnostics = diagnostics
            self.dryRun = dryRun
            self.now = now
        }
    }

    /// V1.108 — drive a full bridge-triage session. Loads existing
    /// decisions, walks each bridge through `readChoice`, upserts
    /// per-invariant records, persists (unless `dryRun`). Returns
    /// the updated `InteractionDecisions` for testability.
    @discardableResult
    public static func run(
        bridges: [BridgeSuggestion],
        packageRoot: URL,
        explicitDecisionsPath: URL? = nil,
        inputs: Inputs
    ) throws -> InteractionDecisions {
        let load = InteractionDecisionsLoader.load(
            startingFrom: packageRoot,
            explicitPath: explicitDecisionsPath
        )
        for warning in load.warnings {
            inputs.diagnostics.writeDiagnostic("warning: \(warning)")
        }
        var decisions = load.decisions
        for (index, bridge) in bridges.enumerated() {
            renderBridge(bridge, position: index + 1, total: bridges.count, inputs: inputs)
            inputs.output.write(promptLine(
                position: index + 1,
                total: bridges.count,
                peerCount: bridge.peers.count
            ))
            let choice = readChoice(
                prompt: inputs.prompt,
                output: inputs.output,
                peerCount: bridge.peers.count
            )
            decisions = applyChoice(
                choice,
                bridge: bridge,
                decisions: decisions,
                output: inputs.output,
                now: inputs.now
            )
        }
        if !inputs.dryRun, decisions != load.decisions {
            let path = explicitDecisionsPath
                ?? InteractionDecisionsLoader.defaultPath(for: load.packageRoot ?? packageRoot)
            try InteractionDecisionsLoader.write(decisions, to: path)
        }
        return decisions
    }

    /// V1.108 — read one valid choice from `prompt`, looping on `?`
    /// (help) and invalid input. Returns `.skip` on EOF as a safe
    /// default (matches v1.98's posture — piped input running out
    /// shouldn't auto-accept anything).
    public static func readChoice(
        prompt: any PromptInput,
        output: any DiscoverOutput,
        peerCount: Int
    ) -> Choice {
        while true {
            output.write("> ")
            guard let line = prompt.readLine() else { return .skip }
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if let choice = parseChoice(trimmed, peerCount: peerCount) {
                return choice
            }
            if trimmed == "?" || trimmed == "h" || trimmed == "help" {
                output.write(helpText(peerCount: peerCount))
                continue
            }
            output.write("Unrecognized input '\(trimmed)'. Type ? for help.")
        }
    }

    /// V1.108 — parse one trimmed-lowercased line into a `Choice`.
    /// Returns nil for unrecognized input (caller loops on help).
    /// Empty / `s` → `.skip` matches v1.98's safe default. Numeric
    /// arm labels must be in `1...peerCount`.
    static func parseChoice(_ trimmed: String, peerCount: Int) -> Choice? {
        switch trimmed {
        case "a": return .acceptAll
        case "s", "": return .skip
        case "n": return .reject
        default:
            if let index = Int(trimmed), index >= 1, index <= peerCount {
                return .acceptPeer(index: index)
            }
            return nil
        }
    }

    /// V1.108 — apply a parsed `Choice` to the running decisions
    /// log. `.skip` leaves the log unchanged. `.acceptAll` /
    /// `.reject` write a record for every invariant in every peer.
    /// `.acceptPeer(index:)` writes records for one peer only.
    static func applyChoice(
        _ choice: Choice,
        bridge: BridgeSuggestion,
        decisions: InteractionDecisions,
        output: any DiscoverOutput,
        now: Date
    ) -> InteractionDecisions {
        switch choice {
        case .skip:
            output.write("Skipped.")
            return decisions
        case .acceptAll:
            let updated = upsertingAllPeers(
                bridge,
                decision: .acceptedAsConformance,
                into: decisions,
                now: now
            )
            output.write("Recorded acceptedAsConformance for all \(bridge.peers.count) peers.")
            return updated
        case .reject:
            let updated = upsertingAllPeers(
                bridge,
                decision: .rejected,
                into: decisions,
                now: now
            )
            output.write("Recorded rejected for all \(bridge.peers.count) peers.")
            return updated
        case .acceptPeer(let index):
            // 1-based → 0-based
            guard index >= 1, index <= bridge.peers.count else {
                output.write("Skipped (invalid peer index \(index)).")
                return decisions
            }
            let peer = bridge.peers[index - 1]
            let updated = upserting(
                peer,
                decision: .acceptedAsConformance,
                into: decisions,
                now: now
            )
            output.write(
                "Recorded acceptedAsConformance for peer #\(index) (\(peer.kitProtocolName))."
            )
            return updated
        }
    }

    /// Fold one peer's invariants into the decisions log with the
    /// given decision. Helper extracted so `applyChoice` stays under
    /// SwiftLint's body-length cap.
    static func upserting(
        _ peer: PeerProposal,
        decision: InteractionDecision,
        into decisions: InteractionDecisions,
        now: Date
    ) -> InteractionDecisions {
        var result = decisions
        for invariant in peer.invariants {
            result = result.upserting(InteractionDecisionRecord(
                identityHash: invariant.identity.normalized,
                family: invariant.family,
                scoreAtDecision: invariant.score,
                tier: invariant.tier,
                reducerQualifiedName: invariant.reducerQualifiedName,
                decision: decision,
                timestamp: now
            ))
        }
        return result
    }

    /// Fold every peer's invariants in `bridge` into the decisions
    /// log with the given decision. Used for `.acceptAll` /
    /// `.reject` arms.
    static func upsertingAllPeers(
        _ bridge: BridgeSuggestion,
        decision: InteractionDecision,
        into decisions: InteractionDecisions,
        now: Date
    ) -> InteractionDecisions {
        var result = decisions
        for peer in bridge.peers {
            result = upserting(peer, decision: decision, into: result, now: now)
        }
        return result
    }

    static func promptLine(position: Int, total: Int, peerCount: Int) -> String {
        let peerArms = (1...peerCount).map(String.init).joined(separator: "/")
        return "[\(position)/\(total)] Accept all (A) / Accept peer (\(peerArms)) / Skip (s) / Reject (n) / Help (?)"
    }

    static func helpText(peerCount: Int) -> String {
        let peerArms = (1...peerCount).map(String.init).joined(separator: ", ")
        return """
        A   — accept all peers as conformance. Records
              `accepted-as-conformance` for every invariant in every peer
              of this bridge.
        \(peerArms) — accept just that peer's invariants. Records
              `accepted-as-conformance` for the chosen peer's invariants
              only; other peers stay undecided and re-surface in future runs.
        s   — skip this bridge for now. No records written; the bridge
              re-surfaces in future --interactive-bridges runs.
              (Also the default if you press Enter.)
        n   — reject all peers. Records `rejected` for every invariant.
        ?   — show this help.
        """
    }

    /// V1.108 — render one bridge's summary block ahead of the
    /// prompt. Pulled out so the orchestrator stays readable + so
    /// tests can pin the rendered shape independently.
    private static func renderBridge(
        _ bridge: BridgeSuggestion,
        position: Int,
        total: Int,
        inputs: Inputs
    ) {
        inputs.output.write("")
        inputs.output.write("[\(position)/\(total)] [Bridge Proposal]")
        inputs.output.write("Reducer:   \(bridge.reducerQualifiedName)")
        inputs.output.write("State:     \(bridge.stateTypeName)")
        inputs.output.write("Identity:  \(bridge.identity.display)")
        inputs.output.write("Peers (\(bridge.peers.count)):")
        for (index, peer) in bridge.peers.enumerated() {
            inputs.output.write("  #\(index + 1) \(peer.kitProtocolName)")
            inputs.output.write("     stub: \(peer.stubTypeName(reducerStateTypeName: bridge.stateTypeName))")
            inputs.output.write("     predicate: \(peer.conjoinedPredicate)")
            inputs.output.write("     invariants: \(peer.invariants.count)")
        }
    }
}
