import Foundation
import PropertyLawKit
import PropertyLawMacro
import Testing

// V1.100 (cycle-97) — repo-side smoke confirming the kit v2.5.0
// `@InteractionInvariantTests` macro expands cleanly through the
// SwiftSyntax-based compiler-plugin path. Mirrors the v1.99
// cycle-96 smoke shape: local conformer + reducer + initial
// state, attached macro, exercise the auto-generated test stub
// via `swift test`.
//
// **Why a separate smoke test, not just kit-side**: kit-side tests
// drive the macro via `assertMacroExpansion` (text-in, text-out
// comparison). Repo-side smoke runs the full macro-expansion +
// compile + execute chain — catches version-skew + plugin-loading
// issues at build time, not at deferred CI time.

@Suite("V1.100 — kit v2.5.0 @InteractionInvariantTests macro smoke")
struct KitV25MacroSmokeTests {

    @Test func macroExpandsAndGeneratedTestRuns() async throws {
        // The `@InteractionInvariantTests` macro attached to
        // `SmokeMacroCardinality` below emits a peer
        // `SmokeMacroCardinalityInteractionInvariantTests` struct
        // containing one auto-generated `@Test`. This test exists
        // to confirm that:
        // 1. The macro plugin loads cleanly (kit v2.5.0 binding).
        // 2. The expanded peer struct compiles against the v2.4.0
        //    harness symbol it references.
        // 3. The user-supplied `initialState` + `reducer` members
        //    satisfy the harness's parameter shape.
        //
        // The auto-generated test runs as part of the same target,
        // so we don't need to invoke it directly — `swift test`
        // picks it up via the @Suite/@Test discovery. The explicit
        // assertion here just confirms the conformer's invariant
        // holds on the initial state (sanity check that the
        // fixture types are well-formed).
        let initial = SmokeMacroState(showsA: false, showsB: false)
        #expect(SmokeMacroCardinality.invariantHolds(in: initial))
    }
}

// MARK: - Fixtures: state + actions

struct SmokeMacroState: Equatable, Sendable {
    var showsA: Bool
    var showsB: Bool
}

enum SmokeMacroAction: CaseIterable, Sendable {
    case showA
    case showB
    case dismissAll
}

enum SmokeMacroFeature {
    static func reduce(_ state: SmokeMacroState, _ action: SmokeMacroAction) -> SmokeMacroState {
        switch action {
        case .showA: return SmokeMacroState(showsA: true, showsB: false)
        case .showB: return SmokeMacroState(showsA: false, showsB: true)
        case .dismissAll: return SmokeMacroState(showsA: false, showsB: false)
        }
    }
}

// MARK: - The macro-attached conformer

/// V1.100 smoke — Cardinality invariant exercising the
/// `@InteractionInvariantTests` macro. The macro emits a peer
/// `SmokeMacroCardinalityInteractionInvariantTests` suite that
/// `swift test` discovers + runs alongside the rest of the
/// SwiftInferCLITests target.
@InteractionInvariantTests
struct SmokeMacroCardinality: CardinalityInvariant, Sendable {
    typealias State = SmokeMacroState
    static let initialState = SmokeMacroState(showsA: false, showsB: false)
    static let reducer: @Sendable (SmokeMacroState, SmokeMacroAction) -> SmokeMacroState =
        SmokeMacroFeature.reduce
    static func invariantHolds(in state: SmokeMacroState) -> Bool {
        (state.showsA ? 1 : 0) + (state.showsB ? 1 : 0) <= 1
    }
}
