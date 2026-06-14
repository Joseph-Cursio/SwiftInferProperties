import Foundation
@testable import SwiftInferCore
import Testing

// Cycle 109 (cycle-108 Blocker A fix) — M1.A signature-scan candidates
// must pre-qualify a bare `State` / `Action` param type to
// `<Enclosing>.State` when it is a type nested in the reducer's enclosing
// type, matching what the M1.B TCA walker already stores. The stub
// emitters (`ActionSequenceStubEmitter`, `InteractionTraceEmitter`)
// construct `State()` / `Action.self` from the stored name verbatim, so a
// bare nested name fails to resolve in the synthesized verifier
// (`cannot find 'State' in scope`). A bare *top-level* type referenced by
// simple name must stay unqualified.

@Suite("ReducerDiscoverer — nested State/Action pre-qualification (cycle 109)")
struct ReducerDiscovererNestedTypeTests {

    @Test("nested State/Action are pre-qualified to <Enclosing>.State for stub emission")
    func nestedStateActionPreQualified() {
        let source = """
        struct Feature {
            struct State { var count: Int }
            enum Action { case refresh }
            static func reduce(_ state: State, _ action: Action) -> State { return state }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].stateTypeName == "Feature.State")
        #expect(result[0].actionTypeName == "Feature.Action")
        // The computed qualified-name property must not double-qualify.
        #expect(result[0].stateQualifiedName == "Feature.State")
        #expect(result[0].actionQualifiedName == "Feature.Action")
    }

    @Test("inout nested State is pre-qualified (the `inout` strip happens first)")
    func nestedInoutStatePreQualified() {
        let source = """
        struct Feature {
            struct State { var count: Int }
            enum Action { case tick }
            static func reduce(_ state: inout State, _ action: Action) { }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].stateTypeName == "Feature.State")
        #expect(result[0].actionTypeName == "Feature.Action")
    }

    @Test("top-level State type referenced from a method stays bare (not mis-qualified)")
    func topLevelStateTypeStaysBare() {
        let source = """
        struct AppState { var count: Int }
        enum AppAction { case refresh }
        enum Logic {
            static func reduce(_ state: AppState, _ action: AppAction) -> AppState { return state }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        // `AppState` / `AppAction` are top-level (not nested in `Logic`),
        // so they must NOT be qualified to `Logic.AppState`.
        #expect(result[0].stateTypeName == "AppState")
        #expect(result[0].actionTypeName == "AppAction")
    }

    @Test("free-function reducer (no enclosing type) stays bare")
    func freeFunctionStaysBare() {
        let source = """
        struct AppState { var count: Int }
        enum AppAction { case refresh }
        func reduce(_ state: AppState, _ action: AppAction) -> AppState { return state }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].enclosingTypeName == nil)
        #expect(result[0].stateTypeName == "AppState")
        #expect(result[0].actionTypeName == "AppAction")
    }
}
