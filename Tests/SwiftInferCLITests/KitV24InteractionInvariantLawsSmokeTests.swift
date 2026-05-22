import Foundation
import PropertyLawKit
import Testing

// V1.99 (cycle-96) — repo-side smoke test confirming the kit's
// new v2.4.0 `checkInteractionInvariantPropertyLaws` +
// `checkActionIdempotenceInvariantPropertyLaws` harnesses are
// reachable + functional from this side of the cross-repo
// boundary. Mirrors the kit-side InteractionInvariantLawsTests
// shape with fixtures local to the repo (avoids depending on the
// kit's @testable internals).
//
// **Why a separate smoke test, not just a kit-side test.** The kit
// owns the harness; SwiftInferProperties owns the consumers (M9
// Bridge writeouts that propose conformer stubs). A repo-side
// smoke confirms the pin actually moved (cycle-96 pin bump 2.2.0 →
// 2.4.0) and the public API surface compiles + runs against the
// repo's Swift / Testing / PropertyBased pin chain — catches
// version-skew issues at build time, not at deferred CI time.

@Suite("V1.99 — kit v2.4.0 InteractionInvariant harness smoke tests")
struct KitV24InteractionInvariantLawsSmokeTests {

    @Test func stateInvariantHarnessReachable() async throws {
        // Positive control — a Cardinality invariant that always
        // holds under the well-behaved reducer. Confirms the kit's
        // `checkInteractionInvariantPropertyLaws` entry compiles +
        // runs from this side. Sanity budget keeps the test under
        // a few hundred milliseconds.
        let results = try await checkInteractionInvariantPropertyLaws(
            for: SmokeCardinality.self,
            initialState: SmokeState(showsA: false, showsB: false),
            reducer: { state, action in SmokeFeature.reduce(state, action) },
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results.allSatisfy { $0.isViolation == false })
        #expect(results[0].protocolLaw == "InteractionInvariant.invariantHoldsAfterEachStep")
    }

    @Test func actionIdempotenceHarnessReachable() async throws {
        // Positive control — `.reset` is genuinely idempotent under
        // the SmokeCounter reducer. Confirms the kit's
        // `checkActionIdempotenceInvariantPropertyLaws` entry
        // compiles + runs from this side.
        let results = try await checkActionIdempotenceInvariantPropertyLaws(
            for: SmokeCounterIdempotence.self,
            initialState: SmokeCounterState(value: 0),
            reducer: { state, action in SmokeCounterFeature.reduce(state, action) },
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results.allSatisfy { $0.isViolation == false })
        #expect(results[0].protocolLaw == "ActionIdempotenceInvariant.doubleApplicationEqualsSingle")
    }
}

// MARK: - Fixtures (local to the smoke test; no dependency on kit @testable internals)

struct SmokeState: Equatable, Sendable {
    var showsA: Bool
    var showsB: Bool
}

enum SmokeAction: CaseIterable, Sendable {
    case showA
    case showB
    case dismissAll
}

/// Cardinality invariant: at most one of two Bools may be true.
struct SmokeCardinality: CardinalityInvariant, Sendable {
    typealias State = SmokeState
    static func invariantHolds(in state: SmokeState) -> Bool {
        (state.showsA ? 1 : 0) + (state.showsB ? 1 : 0) <= 1
    }
}

enum SmokeFeature {
    static func reduce(_ state: SmokeState, _ action: SmokeAction) -> SmokeState {
        switch action {
        case .showA: return SmokeState(showsA: true, showsB: false)
        case .showB: return SmokeState(showsA: false, showsB: true)
        case .dismissAll: return SmokeState(showsA: false, showsB: false)
        }
    }
}

struct SmokeCounterState: Equatable, Sendable {
    var value: Int
}

enum SmokeCounterAction: CaseIterable, Sendable, Hashable {
    case increment
    case decrement
    case reset
}

enum SmokeCounterFeature {
    static func reduce(_ state: SmokeCounterState, _ action: SmokeCounterAction) -> SmokeCounterState {
        switch action {
        case .increment: return SmokeCounterState(value: state.value + 1)
        case .decrement: return SmokeCounterState(value: state.value - 1)
        case .reset: return SmokeCounterState(value: 0)
        }
    }
}

/// Honest conformer — `.reset` is genuinely idempotent (setter shape).
struct SmokeCounterIdempotence: ActionIdempotenceInvariant, Sendable {
    typealias State = SmokeCounterState
    typealias Action = SmokeCounterAction

    static let idempotentActions: Set<SmokeCounterAction> = [.reset]
}
