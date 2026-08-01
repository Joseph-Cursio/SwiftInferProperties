import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// **Same-end access round-trip** — the stack/queue/deque family, transferred from the
/// `known-properties` `[reference]` rows to arbitrary carriers.
///
/// The catalog already *verifies* those laws on stdlib types under `--verify`. What no
/// template could do is look at a user's own container and say it owes the same law.
/// That transfer is what these arms pin.
@Suite("Same-end access round-trip — add at an end, remove from that end")
struct EndedAccessRoundTripTests {

    private static let loc = SourceLocation(file: "Deque.swift", line: 40, column: 1)

    private func addition(
        _ name: String,
        element: String = "Element",
        on carrier: String = "RingBuffer"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: "item", typeText: element, isInout: false)
            ],
            returnTypeText: nil,
            isThrows: false,
            isAsync: false,
            isMutating: true,
            isStatic: false,
            location: Self.loc,
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    private func removal(
        _ name: String,
        returns: String = "Element",
        on carrier: String = "RingBuffer",
        isMutating: Bool = true
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: isMutating,
            isStatic: false,
            location: Self.loc,
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    // MARK: - The shape it exists for

    @Test("append/removeLast on a user carrier is a back-end round-trip")
    func backEndRoundTrip() {
        let shapes = EndedAccessPairing.candidates(
            in: [addition("append"), removal("removeLast")]
        )
        #expect(shapes.count == 1)
        #expect(shapes.first?.end == .back)
        let suggestion = shapes.first.flatMap(EndedAccessRoundTripTemplate.suggest(for:))
        #expect(suggestion?.templateName == "ended-access-round-trip")
        #expect(suggestion?.score.total == 75)
        #expect(suggestion?.score.tier == .strong)
    }

    @Test("prepend/removeFirst is the front-end mirror")
    func frontEndRoundTrip() {
        let shapes = EndedAccessPairing.candidates(
            in: [addition("prepend"), removal("popFirst", returns: "Element?")]
        )
        #expect(shapes.first?.end == .front)
        #expect(shapes.first?.removalIsOptional == true)
        #expect(shapes.first?.lawText.contains(".some(x)") == true)
    }

    /// The restore half is what catches a leaked slot, so it has to be in the law text.
    @Test("The law states the RESTORE, not just the returned value")
    func lawStatesRestore() {
        let shapes = EndedAccessPairing.candidates(
            in: [addition("append"), removal("removeLast")]
        )
        #expect(shapes.first?.lawText.contains("copy == c") == true)
    }

    // MARK: - The two admission gates

    /// **Ends must match.** Back-add with front-remove is a FIFO queue, where this law is
    /// false for any non-empty container.
    @Test("append/removeFirst is a QUEUE and is not proposed")
    func mismatchedEndsDeclined() {
        let shapes = EndedAccessPairing.candidates(
            in: [addition("append"), removal("removeFirst")]
        )
        #expect(shapes.isEmpty)
    }

    /// **Both halves must NAME an end, and this arm is the reason.**
    ///
    /// swift-nio's `PriorityQueue` exposes `push`/`pop`, and `push(x); pop() == x` is
    /// **false** there — `pop` returns the extremum, not the last pushed. A bare `pop`
    /// names no end and cannot be assumed to take one. Found by the population sweep, not
    /// by design; it was the single false positive in seven corpora.
    @Test("push/pop is NOT a same-end pair — the PriorityQueue witness")
    func unnamedEndsDeclined() {
        let shapes = EndedAccessPairing.candidates(
            in: [
                addition("push", on: "PriorityQueue"),
                removal("pop", returns: "Element?", on: "PriorityQueue")
            ]
        )
        #expect(shapes.isEmpty)
        #expect(EndedAccessPairing.additions["push"] == nil)
        #expect(EndedAccessPairing.removals["pop"] == nil)
        #expect(EndedAccessPairing.removals["dequeue"] == nil)
    }

    // MARK: - Shape gates

    @Test("A non-mutating removal is a peek, not a pop")
    func nonMutatingRemovalDeclined() {
        let shapes = EndedAccessPairing.candidates(
            in: [addition("append"), removal("removeLast", isMutating: false)]
        )
        #expect(shapes.isEmpty)
    }

    @Test("A removal returning Void discards the value the law is about")
    func voidRemovalDeclined() {
        let shapes = EndedAccessPairing.candidates(
            in: [addition("append"), removal("removeLast", returns: "Void")]
        )
        #expect(shapes.isEmpty)
    }

    /// `append`/`removeLast` and `append`/`popLast` state the same law twice.
    @Test("One law per carrier, end and element — overloads do not multiply")
    func deduplicatedPerEnd() {
        let shapes = EndedAccessPairing.candidates(in: [
            addition("append"),
            removal("removeLast"),
            removal("popLast", returns: "Element?")
        ])
        #expect(shapes.count == 1)
    }

    /// Both ends on one carrier are two genuinely different laws.
    @Test("A double-ended carrier gets both ends")
    func bothEndsOnOneCarrier() {
        let shapes = EndedAccessPairing.candidates(in: [
            addition("append"), removal("removeLast"),
            addition("prepend"), removal("removeFirst")
        ])
        #expect(Set(shapes.map(\.end)) == [.back, .front])
    }

    // MARK: - Explainability (PRD §4.5)

    /// The kit states these laws over the *concrete* `Deque` — its own doc notes there is
    /// no double-ended protocol to abstract over — so a `Deque` carrier is a
    /// double-report and the caveat says to prefer the kit.
    @Test("The caveats name the restore, the queue confusion, and the Deque overlap")
    func caveatsCarryTheLimits() {
        let shapes = EndedAccessPairing.candidates(
            in: [addition("append"), removal("removeLast")]
        )
        let caveats = shapes.first.map(EndedAccessRoundTripTemplate.makeCaveats(for:)) ?? []
        #expect(caveats.contains { $0.contains("RESTORING the container") })
        #expect(caveats.contains { $0.contains("FIFO queue") })
        #expect(caveats.contains { $0.contains("priority-ordered") })
        #expect(caveats.contains { $0.contains("checkDequeSymmetryPropertyLaws") })
    }

    /// An Optional removal gets the extra arm about the empty container being a separate
    /// property this law says nothing about.
    @Test("An Optional removal adds the empty-container caveat")
    func optionalRemovalCaveat() {
        let shapes = EndedAccessPairing.candidates(
            in: [addition("append"), removal("popLast", returns: "Element?")]
        )
        let caveats = shapes.first.map(EndedAccessRoundTripTemplate.makeCaveats(for:)) ?? []
        #expect(caveats.contains { $0.contains("empty container is a SEPARATE property") })
    }

    @Test("The generator recipe asks for the degenerate containers")
    func generatorRationale() {
        let shapes = EndedAccessPairing.candidates(
            in: [addition("append"), removal("removeLast")]
        )
        let recipes = shapes.first.map(EndedAccessRoundTripTemplate.makeGenerators(for:)) ?? []
        #expect(recipes.first?.rationale.contains("DEGENERATE ONES") == true)
        #expect(recipes.first?.rationale.contains("wrap-around") == true)
    }

    @Test("Identity is distinct per end and stable across rebuilds")
    func identityIsStableAndScoped() {
        func build() -> [SuggestionIdentity] {
            let shapes = EndedAccessPairing.candidates(in: [
                addition("append"), removal("removeLast"),
                addition("prepend"), removal("removeFirst")
            ])
            return shapes.map(EndedAccessRoundTripTemplate.makeIdentity(for:))
        }
        let first = build()
        #expect(Set(first).count == 2, "one identity per end")
        #expect(first == build())
    }
}
