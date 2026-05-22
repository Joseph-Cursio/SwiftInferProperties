import Foundation
@testable import SwiftInferCore
import Testing

// V1.92 (cycle-89) — tests for the M1.A 4th-shape extension
// (`(inout S, A) -> Effect<A>`) + the two-scalar false-positive
// filter. Split from `ReducerDiscovererTests.swift` so each file
// stays under SwiftLint's 400-line cap.

@Suite("ReducerDiscoverer — V1.92 4th-shape + scalar-filter")
struct ReducerDiscovererShape4ScalarTests {

    // MARK: - Shape 4: (inout S, A) -> Effect<A>

    @Test("V1.92 — matches (inout S, A) -> Effect<A> on a method")
    func shape4InoutEffectMethod() {
        // The canonical pre-macro TCA `Reducer.reduce(into:action:)`
        // shape. M1.B's closure walker has caught the same shape
        // inside `Reduce { state, action in ... }` blocks since
        // v1.74; v1.92 extends M1.A's signature scan to catch the
        // method form. Without this, tvOSCaseStudies'
        // `Focus.reduce(into:action:)` and `Root.reduce(into:action:)`
        // measured 0 in cycle-87.
        let source = """
        struct Focus {
            func reduce(into state: inout AppState, action: AppAction) -> Effect<AppAction> {
                return .none
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].signatureShape == .inoutStateActionReturnsEffect)
        #expect(result[0].enclosingTypeName == "Focus")
        #expect(result[0].functionName == "reduce")
    }

    @Test("V1.92 — matches (inout S, A) -> Effect<Module.Action> with namespaced action type arg")
    func shape4InoutEffectNamespacedAction() {
        let source = """
        struct Counter {
            func reduce(into state: inout State, action: Action) -> Effect<Counter.Action> {
                return .none
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].signatureShape == .inoutStateActionReturnsEffect)
    }

    @Test("V1.92 — matches free-function (inout S, A) -> Effect<A> (rare but symmetric)")
    func shape4InoutEffectFreeFunction() {
        let source = """
        func reduce(_ state: inout AppState, _ action: AppAction) -> Effect<AppAction> {
            return .none
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].signatureShape == .inoutStateActionReturnsEffect)
        // Free `(inout S, A) -> Effect<A>` stays `.generic` per V1.C's
        // elm-style differentiation rule (only the pure
        // `.stateActionReturnsState` free form earns `.elmStyle`).
        #expect(result[0].carrierKind == .generic)
    }

    @Test("V1.92 — rejects (inout S, A) -> NotEffect — Effect prefix is required")
    func shape4RejectsNonEffectReturn() {
        let source = """
        func reduce(_ state: inout AppState, _ action: AppAction) -> Publisher<AppAction> {
            return Publisher()
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    // MARK: - Two-scalar false-positive filter

    @Test("V1.92 — rejects (Int, Int) -> Int — both halves scalar")
    func scalarFilterRejectsIntIntInt() {
        // Cycle-87 measured this exact false positive on the
        // hand-rolled corpus's `transform(_ lhs: Int, _ rhs: Int)
        // -> Int` utility (1/8 detections = 12.5% false-positive
        // rate). Scalar filter rejects.
        let source = """
        func transform(_ lhs: Int, _ rhs: Int) -> Int {
            return lhs + rhs
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    @Test("V1.92 — rejects (Bool, Bool) -> Bool")
    func scalarFilterRejectsBoolBoolBool() {
        let source = """
        func combine(_ lhs: Bool, _ rhs: Bool) -> Bool {
            return lhs && rhs
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    @Test("V1.92 — rejects (Int, Int) -> (Int, Effect<Int>) — both halves scalar even in tuple-return")
    func scalarFilterRejectsScalarTupleReturn() {
        let source = """
        func transform(_ lhs: Int, _ rhs: Int) -> (Int, Effect<Int>) {
            return (lhs, .none)
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    @Test("V1.92 — accepts (S, Int) -> S where S is a struct — only scalar+scalar is rejected")
    func scalarFilterAcceptsStructStateScalarAction() {
        // Plausible reducer where State is structured but the Action
        // happens to be a primitive (e.g. `Int` used as a discrete
        // command code). Not the common shape but valid; filter must
        // not over-fire.
        let source = """
        func reduce(_ state: AppState, _ action: Int) -> AppState {
            return state
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].stateTypeName == "AppState")
        #expect(result[0].actionTypeName == "Int")
    }
}
