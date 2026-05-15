import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V2.0 M9 — InteractionBridgeWriter assertions: emit shape +
// canonical writeout path under
// `Tests/Generated/SwiftInferRefactors/`.

@Suite("InteractionBridgeWriter — V2.0 M9 conformance-stub emission")
struct InteractionBridgeWriterTests {

    private let now = ISO8601DateFormatter().date(from: "2026-05-15T12:00:00Z")!

    private func suggestion(
        family: InteractionInvariantFamily,
        predicate: String,
        stateTypeName: String = "Inbox.State",
        actionTypeName: String = "Inbox.Action"
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
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName,
            predicate: predicate,
            score: 80,
            tier: .strong,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: now
        )
    }

    private func bridge(
        with suggestions: [InteractionInvariantSuggestion]
    ) -> (BridgeSuggestion, PeerProposal) {
        let bridges = InteractionInvariantBridge.bridges(from: suggestions, now: now)
        precondition(bridges.count == 1, "test setup must produce exactly one bridge")
        let target = bridges[0]
        precondition(target.peers.count >= 1, "test setup must produce at least one peer")
        return (target, target.peers[0])
    }

    // MARK: - Header + imports

    @Test("first line is the byte-stable header marker — tests can pin the format")
    func firstLineIsHeaderMarker() {
        let (target, peer) = bridge(with: [
            suggestion(family: .cardinality, predicate: "state.isShowingSheet ? 1 : 0 <= 1"),
            suggestion(family: .conservation, predicate: "state.count == state.items.count"),
            suggestion(family: .biconditional, predicate: "state.isLoading == (state.activeTask != nil)")
        ])
        let source = InteractionBridgeWriter.emit(bridge: target, peer: peer)
        let firstLine = source.split(separator: "\n").first.map(String.init) ?? ""
        #expect(firstLine == InteractionBridgeWriter.stubHeaderMarker)
    }

    @Test("emitted stub imports PropertyLawKit (the kit-side family protocol)")
    func emittedStubImportsKit() {
        let (target, peer) = bridge(with: [
            suggestion(family: .cardinality, predicate: "p1"),
            suggestion(family: .conservation, predicate: "p2"),
            suggestion(family: .biconditional, predicate: "p3")
        ])
        let source = InteractionBridgeWriter.emit(bridge: target, peer: peer)
        #expect(source.contains("import PropertyLawKit"))
    }

    // MARK: - State-predicate stub shape (4 families)

    @Test("Cardinality peer emits a `: CardinalityInvariant` conformance stub")
    func cardinalityStubShape() {
        let (target, peer) = bridge(with: [
            suggestion(family: .cardinality, predicate: "p_cardinality"),
            suggestion(family: .conservation, predicate: "p_conservation"),
            suggestion(family: .biconditional, predicate: "p_biconditional")
        ])
        // peer[0] is the Cardinality peer (sorted alphabetically: biconditional,
        // cardinality, conservation). Find the Cardinality peer explicitly.
        let cardinalityPeer = target.peers.first { $0.family == .cardinality }!
        let source = InteractionBridgeWriter.emit(bridge: target, peer: cardinalityPeer)
        #expect(source.contains("struct InboxCardinality: CardinalityInvariant {"))
        #expect(source.contains("typealias State = Inbox.State"))
        #expect(source.contains("static func invariantHolds(in state: State) -> Bool {"))
        #expect(source.contains("p_cardinality"))
    }

    @Test("multi-member peer conjoins predicates with `&&` in invariantHolds body")
    func multiMemberPeerConjoinsPredicates() {
        // 3 distinct families with 2 Cardinality predicates → 1 Cardinality
        // peer covering both via &&.
        let (target, _) = bridge(with: [
            suggestion(family: .cardinality, predicate: "cardA"),
            suggestion(family: .cardinality, predicate: "cardB"),
            suggestion(family: .conservation, predicate: "p_conservation"),
            suggestion(family: .biconditional, predicate: "p_biconditional")
        ])
        let cardinalityPeer = target.peers.first { $0.family == .cardinality }!
        let source = InteractionBridgeWriter.emit(bridge: target, peer: cardinalityPeer)
        #expect(source.contains("cardA && cardB"))
    }

    // MARK: - Idempotence stub shape (idempotentActions Set)

    @Test("ActionIdempotence peer emits idempotentActions Set, not a state predicate")
    func actionIdempotenceStubShape() {
        let (target, _) = bridge(with: [
            suggestion(family: .idempotence, predicate: ".refresh"),
            suggestion(family: .idempotence, predicate: ".reset"),
            suggestion(family: .idempotence, predicate: ".clearAll")
        ])
        let peer = target.peers.first { $0.family == .idempotence }!
        let source = InteractionBridgeWriter.emit(bridge: target, peer: peer)
        #expect(source.contains("struct InboxIdempotence: ActionIdempotenceInvariant {"))
        #expect(source.contains("typealias Action = Inbox.Action"))
        #expect(source.contains("static let idempotentActions: Set<Inbox.Action> = "))
        // Aggregator sorts member invariants by predicate alphabetically
        // for byte-stable output.
        #expect(source.contains(".clearAll, .refresh, .reset"))
        // Idempotence stub does NOT emit invariantHolds — that defaults
        // to true on the kit-side protocol.
        #expect(!source.contains("invariantHolds(in state:"))
    }

    // MARK: - Writeout path

    @Test("stubFilePath lands under Tests/Generated/SwiftInferRefactors/<stateRoot>/<stubName>.swift")
    func stubFilePathLayout() {
        let (target, peer) = bridge(with: [
            suggestion(family: .cardinality, predicate: "p1"),
            suggestion(family: .conservation, predicate: "p2"),
            suggestion(family: .biconditional, predicate: "p3")
        ])
        let cardinalityPeer = target.peers.first { $0.family == .cardinality }!
        let packageRoot = URL(fileURLWithPath: "/tmp/MyPackage", isDirectory: true)
        let path = InteractionBridgeWriter.stubFilePath(
            bridge: target,
            peer: cardinalityPeer,
            packageRoot: packageRoot
        ).path
        #expect(path.hasSuffix(
            "Tests/Generated/SwiftInferRefactors/Inbox/InboxCardinality.swift"
        ))
    }

    @Test("persist writes the stub file under the canonical layout")
    func persistRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InteractionBridgeWriterTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let (target, peer) = bridge(with: [
            suggestion(family: .cardinality, predicate: "p1"),
            suggestion(family: .conservation, predicate: "p2"),
            suggestion(family: .biconditional, predicate: "p3")
        ])
        let path = try InteractionBridgeWriter.persist(
            bridge: target,
            peer: peer,
            packageRoot: directory
        )
        #expect(FileManager.default.fileExists(atPath: path.path))
        let written = try String(contentsOf: path, encoding: .utf8)
        #expect(written.contains(InteractionBridgeWriter.stubHeaderMarker))
    }
}
