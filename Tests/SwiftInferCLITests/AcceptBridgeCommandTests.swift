import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V1.110 (cycle-103d) — tests for the accept-bridge recorder.
// Strong-tier bridges don't fire from real source today (PRD §3.5
// gate), so tests inject synthetic Strong-tier bridges via the
// runWithBridges seam.

@Suite("AcceptBridge — V1.110 bridge-decision recorder")
struct AcceptBridgeCommandTests {

    private typealias Command = SwiftInferCommand.AcceptBridge

    private let now = ISO8601DateFormatter().date(from: "2026-05-17T12:00:00Z")!

    // MARK: - Fixture helpers

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

    // MARK: - parseDecision

    @Test func parseDecisionAcceptsAcceptedAsConformance() throws {
        let result = try Command.parseDecision("accepted-as-conformance")
        #expect(result == .acceptedAsConformance)
    }

    @Test func parseDecisionAcceptsRejected() throws {
        let result = try Command.parseDecision("rejected")
        #expect(result == .rejected)
    }

    @Test func parseDecisionRejectsPlainAcceptedAsNonBridge() {
        do {
            _ = try Command.parseDecision("accepted")
            Issue.record("expected .nonBridgeDecision")
        } catch let error as AcceptBridgeError {
            switch error {
            case .nonBridgeDecision: break
            default: Issue.record("expected .nonBridgeDecision; got \(error)")
            }
        } catch {
            Issue.record("expected AcceptBridgeError; got \(error)")
        }
    }

    @Test func parseDecisionRejectsSkippedAsNonBridge() {
        do {
            _ = try Command.parseDecision("skipped")
            Issue.record("expected .nonBridgeDecision")
        } catch let error as AcceptBridgeError {
            switch error {
            case .nonBridgeDecision: break
            default: Issue.record("expected .nonBridgeDecision; got \(error)")
            }
        } catch {
            Issue.record("expected AcceptBridgeError; got \(error)")
        }
    }

    @Test func parseDecisionRejectsUnknownString() {
        do {
            _ = try Command.parseDecision("bogus")
            Issue.record("expected .unknownDecision")
        } catch let error as AcceptBridgeError {
            switch error {
            case .unknownDecision: break
            default: Issue.record("expected .unknownDecision; got \(error)")
            }
        } catch {
            Issue.record("expected AcceptBridgeError; got \(error)")
        }
    }

    // MARK: - resolveScope

    @Test func resolveScopeNilPeerReturnsAllPeerInvariants() throws {
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1"),
            makePeer(family: .biconditional, predicate: "p2"),
            makePeer(family: .conservation, predicate: "p3")
        ])
        let result = try Command.resolveScope(bridge: bridge, peerIndex: nil)
        #expect(result.count == 3)
    }

    @Test func resolveScopeValidPeerReturnsThatPeersInvariants() throws {
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1"),
            makePeer(family: .biconditional, predicate: "p2")
        ])
        let result = try Command.resolveScope(bridge: bridge, peerIndex: 2)
        #expect(result.count == 1)
        #expect(result[0].family == .biconditional)
    }

    @Test func resolveScopePeerOutOfRangeErrors() {
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1")
        ])
        do {
            _ = try Command.resolveScope(bridge: bridge, peerIndex: 5)
            Issue.record("expected .peerOutOfRange")
        } catch let error as AcceptBridgeError {
            switch error {
            case let .peerOutOfRange(index, peerCount):
                #expect(index == 5)
                #expect(peerCount == 1)
            default: Issue.record("expected .peerOutOfRange; got \(error)")
            }
        } catch {
            Issue.record("expected AcceptBridgeError; got \(error)")
        }
    }

    @Test func resolveScopePeerZeroErrors() {
        let bridge = makeBridge(peers: [makePeer(family: .cardinality, predicate: "p1")])
        do {
            _ = try Command.resolveScope(bridge: bridge, peerIndex: 0)
            Issue.record("expected .peerOutOfRange")
        } catch let error as AcceptBridgeError {
            switch error {
            case .peerOutOfRange: break
            default: Issue.record("expected .peerOutOfRange; got \(error)")
            }
        } catch {
            Issue.record("expected AcceptBridgeError; got \(error)")
        }
    }

    // MARK: - CLI registration

    @Test func acceptBridgeIsRegisteredInSubcommands() {
        let names = SwiftInferCommand.configuration.subcommands.map {
            $0.configuration.commandName ?? ""
        }
        #expect(names.contains("accept-bridge"))
    }

    @Test func acceptBridgeRequiresTargetAndIdentityAndDecision() {
        #expect(throws: (any Error).self) {
            _ = try Command.parse([])
        }
    }

    @Test func acceptBridgeParsesAllFlags() throws {
        let parsed = try Command.parse([
            "--target", "MyApp",
            "--identity", "ABCD1234567890EF",
            "--decision", "accepted-as-conformance",
            "--peer", "2",
            "--decisions", "/tmp/foo.json"
        ])
        #expect(parsed.target == "MyApp")
        #expect(parsed.identity == "ABCD1234567890EF")
        #expect(parsed.decision == "accepted-as-conformance")
        #expect(parsed.peer == 2)
        #expect(parsed.decisions == "/tmp/foo.json")
    }

}

final class ABRecordingOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    var text: String { lines.joined(separator: "\n") }
    func write(_ text: String) {
        lines.append(text)
    }
}
