import Foundation
import Testing
@testable import SwiftInferCore

// V2.0 M9 — InteractionInvariantBridge aggregator. Pure: no I/O.
// Uses synthetic Strong-tier `InteractionInvariantSuggestion`
// inputs because PRD §3.5's calibration rule keeps every family at
// default-`.possible` until promotion; no Strong-tier invariants
// exist in production yet.

@Suite("InteractionInvariantBridge — V2.0 M9 aggregator")
struct InteractionInvariantBridgeTests {

    private let now = ISO8601DateFormatter().date(from: "2026-05-15T12:00:00Z")!

    private func suggestion(
        family: InteractionInvariantFamily,
        reducerQualifiedName: String,
        predicate: String,
        tier: Tier = .strong
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: family,
            reducerQualifiedName: reducerQualifiedName,
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: family,
            reducerQualifiedName: reducerQualifiedName,
            reducerLocation: "F.swift:1",
            stateTypeName: "Inbox.State",
            actionTypeName: "Inbox.Action",
            predicate: predicate,
            score: 80,
            tier: tier,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: now
        )
    }

    // MARK: - Threshold gating

    @Test("no Bridge fires below the threshold (≥ 3 Strong required)")
    func belowThresholdNoBridge() {
        let suggestions = [
            suggestion(family: .cardinality, reducerQualifiedName: "Inbox.body", predicate: "p1"),
            suggestion(family: .conservation, reducerQualifiedName: "Inbox.body", predicate: "p2")
        ]
        let bridges = InteractionInvariantBridge.bridges(from: suggestions, now: now)
        #expect(bridges.isEmpty)
    }

    @Test("Bridge fires at exactly 3 Strong on the same reducer")
    func exactlyThreeStrongFires() {
        let suggestions = [
            suggestion(family: .cardinality, reducerQualifiedName: "Inbox.body", predicate: "p1"),
            suggestion(family: .conservation, reducerQualifiedName: "Inbox.body", predicate: "p2"),
            suggestion(family: .biconditional, reducerQualifiedName: "Inbox.body", predicate: "p3")
        ]
        let bridges = InteractionInvariantBridge.bridges(from: suggestions, now: now)
        #expect(bridges.count == 1)
        #expect(bridges[0].reducerQualifiedName == "Inbox.body")
        #expect(bridges[0].peers.count == 3)
    }

    @Test("non-Strong tier suggestions are excluded from the count")
    func nonStrongExcluded() {
        let suggestions = [
            suggestion(family: .cardinality, reducerQualifiedName: "Inbox.body", predicate: "p1"),
            suggestion(family: .conservation, reducerQualifiedName: "Inbox.body", predicate: "p2"),
            suggestion(
                family: .biconditional,
                reducerQualifiedName: "Inbox.body",
                predicate: "p3",
                tier: .possible
            )
        ]
        let bridges = InteractionInvariantBridge.bridges(from: suggestions, now: now)
        #expect(bridges.isEmpty)
    }

    @Test("Verified tier counts toward the threshold (verified is Strong+)")
    func verifiedCountsAsStrong() {
        let suggestions = [
            suggestion(family: .cardinality, reducerQualifiedName: "Inbox.body", predicate: "p1"),
            suggestion(family: .conservation, reducerQualifiedName: "Inbox.body", predicate: "p2"),
            suggestion(
                family: .biconditional,
                reducerQualifiedName: "Inbox.body",
                predicate: "p3",
                tier: .verified
            )
        ]
        let bridges = InteractionInvariantBridge.bridges(from: suggestions, now: now)
        #expect(bridges.count == 1)
    }

    // MARK: - Peer-proposal shape

    @Test("4 Strong invariants in a single family → 1 peer proposal")
    func singleFamilyMultipleInvariantsOnePeer() {
        let suggestions = (0..<4).map {
            suggestion(
                family: .cardinality,
                reducerQualifiedName: "Inbox.body",
                predicate: "p\($0)"
            )
        }
        let bridges = InteractionInvariantBridge.bridges(from: suggestions, now: now)
        #expect(bridges.count == 1)
        #expect(bridges[0].peers.count == 1)
        #expect(bridges[0].peers[0].family == .cardinality)
        #expect(bridges[0].peers[0].invariants.count == 4)
    }

    @Test("peer proposals are sorted by family.rawValue for byte-stable rendering")
    func peerSortStability() {
        let suggestions = [
            suggestion(family: .conservation, reducerQualifiedName: "Inbox.body", predicate: "c1"),
            suggestion(family: .biconditional, reducerQualifiedName: "Inbox.body", predicate: "b1"),
            suggestion(family: .cardinality, reducerQualifiedName: "Inbox.body", predicate: "card1")
        ]
        let bridges = InteractionInvariantBridge.bridges(from: suggestions, now: now)
        #expect(bridges.count == 1)
        let familyRaws = bridges[0].peers.map(\.family.rawValue)
        #expect(familyRaws == familyRaws.sorted())
    }

    // MARK: - Multi-reducer isolation

    @Test("Bridges don't cross-link across reducers")
    func reducerIsolation() {
        let suggestions = [
            suggestion(family: .cardinality, reducerQualifiedName: "Inbox.body", predicate: "i1"),
            suggestion(family: .conservation, reducerQualifiedName: "Inbox.body", predicate: "i2"),
            // Settings has only 1 Strong invariant → below threshold
            suggestion(family: .cardinality, reducerQualifiedName: "Settings.body", predicate: "s1")
        ]
        let bridges = InteractionInvariantBridge.bridges(from: suggestions, now: now)
        // Inbox has 2 strong; threshold is 3 → no bridge.
        // Settings has 1 strong → no bridge.
        #expect(bridges.isEmpty)
    }

    @Test("two reducers each meeting threshold each get their own Bridge")
    func multiBridgeSorting() {
        var suggestions: [InteractionInvariantSuggestion] = []
        for family in [
            InteractionInvariantFamily.cardinality,
            .conservation,
            .biconditional
        ] {
            suggestions.append(suggestion(
                family: family,
                reducerQualifiedName: "Inbox.body",
                predicate: "i-\(family.rawValue)"
            ))
            suggestions.append(suggestion(
                family: family,
                reducerQualifiedName: "Settings.body",
                predicate: "s-\(family.rawValue)"
            ))
        }
        let bridges = InteractionInvariantBridge.bridges(from: suggestions, now: now)
        #expect(bridges.count == 2)
        // Output sorted by reducer qualified name.
        #expect(bridges[0].reducerQualifiedName == "Inbox.body")
        #expect(bridges[1].reducerQualifiedName == "Settings.body")
    }

    // MARK: - Identity stability

    @Test("Bridge identity is stable across re-aggregation with the same inputs")
    func identityStability() {
        let suggestions = [
            suggestion(family: .cardinality, reducerQualifiedName: "Inbox.body", predicate: "p1"),
            suggestion(family: .conservation, reducerQualifiedName: "Inbox.body", predicate: "p2"),
            suggestion(family: .biconditional, reducerQualifiedName: "Inbox.body", predicate: "p3")
        ]
        let first = InteractionInvariantBridge.bridges(from: suggestions, now: now)
        let second = InteractionInvariantBridge.bridges(from: suggestions, now: now)
        #expect(first.first?.identity == second.first?.identity)
    }

    @Test("Bridge identity is order-independent — the family list is sorted before hashing")
    func identityOrderIndependent() {
        let base = [
            suggestion(family: .cardinality, reducerQualifiedName: "Inbox.body", predicate: "p1"),
            suggestion(family: .conservation, reducerQualifiedName: "Inbox.body", predicate: "p2"),
            suggestion(family: .biconditional, reducerQualifiedName: "Inbox.body", predicate: "p3")
        ]
        let reordered = Array(base.reversed())
        let baseBridge = InteractionInvariantBridge.bridges(from: base, now: now).first
        let reorderedBridge = InteractionInvariantBridge.bridges(from: reordered, now: now).first
        #expect(baseBridge?.identity == reorderedBridge?.identity)
    }

    // MARK: - kitProtocolName mapping

    @Test("kitProtocolName mirrors SwiftPropertyLaws v2.3.0's InteractionInvariant.swift")
    func kitProtocolNameMapping() {
        #expect(kitProtocolName(for: .conservation) == "ConservationInvariant")
        #expect(kitProtocolName(for: .idempotence) == "ActionIdempotenceInvariant")
        #expect(kitProtocolName(for: .cardinality) == "CardinalityInvariant")
        #expect(kitProtocolName(for: .referentialIntegrity) == "ReferentialIntegrityInvariant")
        #expect(kitProtocolName(for: .biconditional) == "BiconditionalInvariant")
    }
}
