import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V1.108 (cycle-103b) — tests for the bridge-level N-arm
// interactive triage namespace.

@Suite("InteractionBridgeInteractiveTriage — V1.108 N-arm bridge triage")
struct BridgeTriageTests {

    private let now = ISO8601DateFormatter().date(from: "2026-05-17T12:00:00Z")!

    // MARK: - Fixture helpers

    private func makeInvariant(
        family: InteractionInvariantFamily,
        reducer: String,
        predicate: String
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: family,
            reducerQualifiedName: reducer,
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: family,
            reducerQualifiedName: reducer,
            reducerLocation: "F.swift:1",
            stateTypeName: "Inbox.State",
            actionTypeName: "Inbox.Action",
            predicate: predicate,
            score: 80,
            tier: .strong,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: now
        )
    }

    private func makePeer(
        family: InteractionInvariantFamily,
        predicate: String
    ) -> PeerProposal {
        PeerProposal(
            family: family,
            kitProtocolName: kitProtocolName(for: family),
            invariants: [makeInvariant(family: family, reducer: "Inbox.body", predicate: predicate)]
        )
    }

    private func makeBridge(peers: [PeerProposal]) -> BridgeSuggestion {
        let families = peers.map(\.family)
        let canonical = BridgeSuggestion.identityCanonicalInput(
            reducerQualifiedName: "Inbox.body",
            families: families
        )
        return BridgeSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            reducerQualifiedName: "Inbox.body",
            stateTypeName: "Inbox.State",
            peers: peers,
            firstSeenAt: now
        )
    }

    // MARK: - parseChoice — arm classification

    @Test func parseChoiceMapsArms() {
        let peerCount = 3
        let table: [(String, InteractionBridgeInteractiveTriage.Choice?)] = [
            ("a", .acceptAll),
            ("A", nil),                // case sensitivity: caller pre-lowercases
            ("s", .skip),
            ("", .skip),               // empty = skip (Enter default)
            ("n", .reject),
            ("1", .acceptPeer(index: 1)),
            ("2", .acceptPeer(index: 2)),
            ("3", .acceptPeer(index: 3)),
            ("4", nil),                // out of range
            ("0", nil),                // out of range
            ("x", nil)                 // unrecognized
        ]
        for (input, expected) in table {
            let result = InteractionBridgeInteractiveTriage.parseChoice(
                input,
                peerCount: peerCount
            )
            #expect(result == expected, "input '\(input)' should map to \(String(describing: expected))")
        }
    }

    // MARK: - readChoice — full prompt loop

    @Test func readChoiceLoopsOnHelpThenAcceptsValidInput() {
        let prompt = TriageRecordingPromptInput(scriptedLines: ["?", "a"])
        let output = TriageRecordingOutput()
        let choice = InteractionBridgeInteractiveTriage.readChoice(
            prompt: prompt,
            output: output,
            peerCount: 2
        )
        #expect(choice == .acceptAll)
        #expect(output.text.contains("accept just that peer"))
    }

    @Test func readChoiceFallsThroughOnUnrecognized() {
        let prompt = TriageRecordingPromptInput(scriptedLines: ["xyz", "1"])
        let output = TriageRecordingOutput()
        let choice = InteractionBridgeInteractiveTriage.readChoice(
            prompt: prompt,
            output: output,
            peerCount: 3
        )
        #expect(choice == .acceptPeer(index: 1))
        #expect(output.text.contains("Unrecognized input 'xyz'"))
    }

    @Test func readChoiceReturnsSkipOnEOF() {
        let prompt = TriageRecordingPromptInput(scriptedLines: [])
        let output = TriageRecordingOutput()
        let choice = InteractionBridgeInteractiveTriage.readChoice(
            prompt: prompt,
            output: output,
            peerCount: 2
        )
        #expect(choice == .skip)
    }

    // MARK: - applyChoice — decision persistence

    @Test func acceptAllRecordsConformanceForAllPeerInvariants() {
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1"),
            makePeer(family: .biconditional, predicate: "p2")
        ])
        let output = TriageRecordingOutput()
        let result = InteractionBridgeInteractiveTriage.applyChoice(
            .acceptAll,
            bridge: bridge,
            decisions: .empty,
            output: output,
            now: now
        )
        #expect(result.records.count == 2)
        #expect(result.records.allSatisfy { $0.decision == .acceptedAsConformance })
        #expect(output.text.contains("Recorded acceptedAsConformance for all 2 peers"))
    }

    @Test func rejectRecordsRejectedForAllPeerInvariants() {
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1"),
            makePeer(family: .biconditional, predicate: "p2"),
            makePeer(family: .conservation, predicate: "p3")
        ])
        let output = TriageRecordingOutput()
        let result = InteractionBridgeInteractiveTriage.applyChoice(
            .reject,
            bridge: bridge,
            decisions: .empty,
            output: output,
            now: now
        )
        #expect(result.records.count == 3)
        #expect(result.records.allSatisfy { $0.decision == .rejected })
        #expect(output.text.contains("Recorded rejected for all 3 peers"))
    }

    @Test func acceptPeerRecordsOnlyThatPeersInvariants() {
        let cardinality = makePeer(family: .cardinality, predicate: "p1")
        let biconditional = makePeer(family: .biconditional, predicate: "p2")
        let conservation = makePeer(family: .conservation, predicate: "p3")
        let bridge = makeBridge(peers: [cardinality, biconditional, conservation])
        let output = TriageRecordingOutput()
        let result = InteractionBridgeInteractiveTriage.applyChoice(
            .acceptPeer(index: 2),
            bridge: bridge,
            decisions: .empty,
            output: output,
            now: now
        )
        #expect(result.records.count == 1)
        #expect(result.records[0].family == .biconditional)
        #expect(result.records[0].decision == .acceptedAsConformance)
        #expect(output.text.contains("peer #2"))
    }

    @Test func skipLeavesDecisionsUnchanged() {
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1"),
            makePeer(family: .biconditional, predicate: "p2")
        ])
        let initialDecisions = InteractionDecisions.empty
        let output = TriageRecordingOutput()
        let result = InteractionBridgeInteractiveTriage.applyChoice(
            .skip,
            bridge: bridge,
            decisions: initialDecisions,
            output: output,
            now: now
        )
        #expect(result == initialDecisions)
        #expect(output.text.contains("Skipped"))
    }

    @Test func acceptPeerOutOfRangeIsNoOp() {
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1")
        ])
        let output = TriageRecordingOutput()
        let result = InteractionBridgeInteractiveTriage.applyChoice(
            .acceptPeer(index: 99),
            bridge: bridge,
            decisions: .empty,
            output: output,
            now: now
        )
        #expect(result == .empty)
        #expect(output.text.contains("invalid peer index"))
    }

    // MARK: - Multi-invariant peer

    @Test func peerWithMultipleInvariantsRecordsAll() {
        let multiInvariantPeer = PeerProposal(
            family: .cardinality,
            kitProtocolName: "CardinalityInvariant",
            invariants: [
                makeInvariant(family: .cardinality, reducer: "Inbox.body", predicate: "p1"),
                makeInvariant(family: .cardinality, reducer: "Inbox.body", predicate: "p2")
            ]
        )
        let bridge = makeBridge(peers: [multiInvariantPeer])
        let output = TriageRecordingOutput()
        let result = InteractionBridgeInteractiveTriage.applyChoice(
            .acceptPeer(index: 1),
            bridge: bridge,
            decisions: .empty,
            output: output,
            now: now
        )
        // Both invariants in the single peer should land in the decisions log.
        #expect(result.records.count == 2)
    }

    // MARK: - promptLine + helpText rendering

    @Test func promptLineEnumeratesPeerArms() {
        let line = InteractionBridgeInteractiveTriage.promptLine(
            position: 1,
            total: 3,
            peerCount: 3
        )
        #expect(line.contains("[1/3]"))
        #expect(line.contains("(1/2/3)"))
    }

    @Test func helpTextEnumeratesPeerArms() {
        let help = InteractionBridgeInteractiveTriage.helpText(peerCount: 4)
        #expect(help.contains("1, 2, 3, 4"))
        #expect(help.contains("A   — accept all peers"))
        #expect(help.contains("n   — reject all peers"))
    }
}
