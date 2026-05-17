import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V1.110 (cycle-103d) — end-to-end pipeline tests for the accept-
// bridge recorder via the runWithBridges seam. Split out from
// AcceptBridgeCommandTests.swift to stay under SwiftLint's
// type_body_length cap.

@Suite("AcceptBridge — V1.110 runWithBridges pipeline")
struct AcceptBridgePipelineTests {

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

    private func tempFixturePackage(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcceptBridgePipelineTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: root.appendingPathComponent("Package.swift")
        )
        return root
    }

    private func readPersistedDecisions(at root: URL) throws -> InteractionDecisions {
        let path = root.appendingPathComponent(".swiftinfer/interaction-decisions.json")
        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InteractionDecisions.self, from: data)
    }

    @Test func runWithBridgesAcceptAllRecordsConformanceForEveryInvariant() throws {
        let root = try tempFixturePackage(name: "AcceptAll")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("X")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1"),
            makePeer(family: .biconditional, predicate: "p2")
        ])
        let output = ABRecordingOutput()

        try Command.runWithBridges(
            bridges: [bridge],
            directory: directory,
            request: AcceptBridgeRequest(
                identity: bridge.identity.normalized,
                decisionRaw: "accepted-as-conformance"
            ),
            output: output,
            now: now
        )

        let decisions = try readPersistedDecisions(at: root)
        #expect(decisions.records.count == 2)
        #expect(decisions.records.allSatisfy { $0.decision == .acceptedAsConformance })
        #expect(output.text.contains("all 2 peers"))
    }

    @Test func runWithBridgesAcceptOnePeerRecordsOnlyThatPeer() throws {
        let root = try tempFixturePackage(name: "AcceptPeer")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("X")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1"),
            makePeer(family: .biconditional, predicate: "p2"),
            makePeer(family: .conservation, predicate: "p3")
        ])
        let output = ABRecordingOutput()

        try Command.runWithBridges(
            bridges: [bridge],
            directory: directory,
            request: AcceptBridgeRequest(
                identity: bridge.identity.normalized,
                decisionRaw: "accepted-as-conformance",
                peerIndex: 2
            ),
            output: output,
            now: now
        )

        let decisions = try readPersistedDecisions(at: root)
        #expect(decisions.records.count == 1)
        #expect(decisions.records[0].family == .biconditional)
        #expect(output.text.contains("peer #2"))
    }

    @Test func runWithBridgesUnknownIdentityErrors() throws {
        let root = try tempFixturePackage(name: "UnknownIdentity")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("X")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1"),
            makePeer(family: .biconditional, predicate: "p2")
        ])
        do {
            try Command.runWithBridges(
                bridges: [bridge],
                directory: directory,
                request: AcceptBridgeRequest(
                    identity: "DEADBEEFDEADBEEF",
                    decisionRaw: "accepted-as-conformance"
                ),
                output: ABRecordingOutput(),
                now: now
            )
            Issue.record("expected .unknownBridgeIdentity")
        } catch let error as AcceptBridgeError {
            switch error {
            case let .unknownBridgeIdentity(hash):
                #expect(hash == "DEADBEEFDEADBEEF")
            default: Issue.record("expected .unknownBridgeIdentity; got \(error)")
            }
        }
    }

    @Test func runWithBridgesRejectAllRecordsRejectedForEachInvariant() throws {
        let root = try tempFixturePackage(name: "RejectAll")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("X")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1"),
            makePeer(family: .biconditional, predicate: "p2"),
            makePeer(family: .conservation, predicate: "p3")
        ])

        try Command.runWithBridges(
            bridges: [bridge],
            directory: directory,
            request: AcceptBridgeRequest(
                identity: bridge.identity.normalized,
                decisionRaw: "rejected"
            ),
            output: ABRecordingOutput(),
            now: now
        )

        let decisions = try readPersistedDecisions(at: root)
        #expect(decisions.records.count == 3)
        #expect(decisions.records.allSatisfy { $0.decision == .rejected })
    }

    @Test func runWithBridgesIdentityHashIsCaseInsensitive() throws {
        let root = try tempFixturePackage(name: "CaseInsensitive")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("X")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bridge = makeBridge(peers: [
            makePeer(family: .cardinality, predicate: "p1"),
            makePeer(family: .biconditional, predicate: "p2")
        ])
        // runWithBridges uppercases the identity before matching,
        // mirroring accept-interaction's behavior. Pass lowercase to
        // verify the case-insensitive lookup.
        let lowercaseHash = bridge.identity.normalized.lowercased()

        try Command.runWithBridges(
            bridges: [bridge],
            directory: directory,
            request: AcceptBridgeRequest(
                identity: lowercaseHash,
                decisionRaw: "accepted-as-conformance"
            ),
            output: ABRecordingOutput(),
            now: now
        )

        let path = root.appendingPathComponent(".swiftinfer/interaction-decisions.json")
        #expect(FileManager.default.fileExists(atPath: path.path))
    }
}
