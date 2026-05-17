import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V1.107 (cycle-103 Finding F fix) — regression tests for the
// candidate-dedupe-by-state-action helper in DiscoverInteraction.
// Pure: no I/O, no template-engine invocation.

@Suite("DiscoverInteraction — V1.107 candidate dedupe by state+action")
struct DiscoverInteractionDedupeTests {

    private typealias Command = SwiftInferCommand.DiscoverInteraction

    private func candidate(
        location: String = "/tmp/a.swift:1",
        functionName: String = "body",
        stateName: String = "State",
        actionName: String = "Action",
        enclosing: String? = nil
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: location,
            enclosingTypeName: enclosing,
            functionName: functionName,
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: stateName,
            actionTypeName: actionName,
            carrierKind: .tca,
            purity: .pure
        )
    }

    @Test func twoCandidatesSameStateAndActionDedupedToOne() {
        // Mirrors the isowords Settings.body case: 10 inline
        // `Reduce { ... }` closures with the same Settings.State +
        // Settings.Action emit 10 candidates. The dedupe collapses
        // them to 1 (first-seen wins) so the template engine runs
        // only once.
        let first = candidate(location: "/tmp/s.swift:10", enclosing: "Settings")
        let second = candidate(location: "/tmp/s.swift:20", enclosing: "Settings")
        let third = candidate(location: "/tmp/s.swift:30", enclosing: "Settings")

        let result = Command.dedupedByStateAndAction([first, second, third])

        #expect(result.count == 1)
        #expect(result[0].location == "/tmp/s.swift:10")
    }

    @Test func distinctStateOrActionPreservedSeparately() {
        // Two different Reducer types with different State / Action.
        // The dedupe must not collapse them.
        let foo = candidate(enclosing: "Foo")
        let bar = candidate(enclosing: "Bar")

        let result = Command.dedupedByStateAndAction([foo, bar])

        #expect(result.count == 2)
        let enclosings = Set(result.compactMap(\.enclosingTypeName))
        #expect(enclosings == ["Foo", "Bar"])
    }

    @Test func sameStateDifferentActionPreserved() {
        // Edge case: two Reducer types share a State alias but
        // have different Actions. The dedupe should not collapse —
        // the predicate engine examines both halves.
        let candA = candidate(
            stateName: "SharedState",
            actionName: "ActionA",
            enclosing: "Wrapper"
        )
        let candB = candidate(
            stateName: "SharedState",
            actionName: "ActionB",
            enclosing: "Wrapper"
        )

        let result = Command.dedupedByStateAndAction([candA, candB])

        #expect(result.count == 2)
    }

    @Test func sameActionDifferentStatePreserved() {
        // Mirror of the above: shared Action name, different State.
        let candA = candidate(
            stateName: "StateA",
            actionName: "SharedAction",
            enclosing: "Wrapper"
        )
        let candB = candidate(
            stateName: "StateB",
            actionName: "SharedAction",
            enclosing: "Wrapper"
        )

        let result = Command.dedupedByStateAndAction([candA, candB])

        #expect(result.count == 2)
    }

    @Test func emptyInputReturnsEmpty() {
        let result = Command.dedupedByStateAndAction([])
        #expect(result.isEmpty)
    }

    @Test func singleCandidateUnchanged() {
        let only = candidate()
        let result = Command.dedupedByStateAndAction([only])
        #expect(result.count == 1)
        #expect(result[0].location == only.location)
    }

    @Test func firstSeenOrderingPreserved() {
        // The first-seen-wins semantics must produce a stable
        // ordering so downstream consumers (template engine,
        // identity hashing) see deterministic input.
        let candA = candidate(location: "/tmp/x.swift:1", enclosing: "A")
        let candB = candidate(location: "/tmp/x.swift:2", enclosing: "B")
        let aDuplicate = candidate(location: "/tmp/x.swift:3", enclosing: "A")
        let candC = candidate(location: "/tmp/x.swift:4", enclosing: "C")

        let result = Command.dedupedByStateAndAction([candA, candB, aDuplicate, candC])

        #expect(result.count == 3)
        #expect(result.map(\.location) == [
            "/tmp/x.swift:1",
            "/tmp/x.swift:2",
            "/tmp/x.swift:4"
        ])
    }
}
