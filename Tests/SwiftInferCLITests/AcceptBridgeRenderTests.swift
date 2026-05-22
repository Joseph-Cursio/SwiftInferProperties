import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// V1.110 (cycle-103d) — renderSummary tests for the accept-bridge
// recorder. Split out from AcceptBridgeCommandTests.swift to stay
// under SwiftLint's type_body_length cap after the end-to-end
// pipeline tests inflated the main test struct.

@Suite("AcceptBridge — V1.110 renderSummary")
struct AcceptBridgeRenderTests {

    private typealias Command = SwiftInferCommand.AcceptBridge

    private let now = ISO8601DateFormatter().date(from: "2026-05-17T12:00:00Z")!

    private func makeInvariant(
        family: InteractionInvariantFamily,
        predicate: String
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: family,
            reducerQualifiedName: "Inbox.body",
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: family,
            reducerQualifiedName: "Inbox.body",
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
            invariants: [makeInvariant(family: family, predicate: predicate)]
        )
    }

    private func makeBridge(peers: [PeerProposal]) -> BridgeSuggestion {
        let families = peers.map(\.family)
        return BridgeSuggestion(
            identity: SuggestionIdentity(canonicalInput:
                BridgeSuggestion.identityCanonicalInput(
                    reducerQualifiedName: "Inbox.body",
                    families: families
                )),
            reducerQualifiedName: "Inbox.body",
            stateTypeName: "Inbox.State",
            peers: peers,
            firstSeenAt: now
        )
    }

    @Test func renderSummaryAllPeers() {
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1"),
            makePeer(family: .biconditional, predicate: "p2")
        ])
        let summary = Command.renderSummary(
            decision: .acceptedAsConformance,
            bridge: bridge,
            peerIndex: nil,
            recordedCount: 2
        )
        #expect(summary.contains("accepted-as-conformance"))
        #expect(summary.contains("all 2 peers"))
        #expect(summary.contains("Inbox.body"))
        #expect(summary.contains("2 invariants"))
    }

    @Test func renderSummaryScopedToPeer() {
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1"),
            makePeer(family: .biconditional, predicate: "p2")
        ])
        let summary = Command.renderSummary(
            decision: .rejected,
            bridge: bridge,
            peerIndex: 1,
            recordedCount: 1
        )
        #expect(summary.contains("rejected"))
        #expect(summary.contains("peer #1"))
        #expect(summary.contains("CardinalityInvariant"))
    }
}
