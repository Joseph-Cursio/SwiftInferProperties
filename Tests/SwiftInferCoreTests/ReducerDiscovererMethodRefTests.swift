import Foundation
import Testing
@testable import SwiftInferCore

// Finding I from kitlangton/Hex dogfood (cycle-dogfood-hex). Tests
// the method-reference form of TCA's `Reduce(...)` — `Reduce(reduce)`
// where the conformer extracts the body into a separate method rather
// than an inline closure. Common idiom when reducer logic grows
// beyond a comfortable closure size. Sibling to
// `ReducerDiscovererTCATests` (closure form) +
// `ReducerDiscovererMacroAttributeTests` (M1.D macro form).

@Suite("ReducerDiscoverer — Finding I method-reference Reduce form")
struct ReducerDiscovererMethodRefTests {

    @Test("matches Reduce(methodName) — Hex's ModelDownloadFeature shape")
    func methodReferenceBasic() {
        let source = """
        import ComposableArchitecture

        @Reducer
        public struct ModelDownloadFeature {
            public struct State {}
            public enum Action {}
            public var body: some ReducerOf<Self> {
                BindingReducer()
                Reduce(reduce)
            }
            private func reduce(into state: inout State, action: Action) -> Effect<Action> {
                return .none
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "ModelDownloadFeature.swift")
        #expect(result.count == 1)
        let candidate = result[0]
        #expect(candidate.carrierKind == .tca)
        #expect(candidate.signatureShape == .inoutStateActionReturnsEffect)
        #expect(candidate.enclosingTypeName == "ModelDownloadFeature")
        #expect(candidate.functionName == "body")
        #expect(candidate.stateTypeName == "ModelDownloadFeature.State")
        #expect(candidate.actionTypeName == "ModelDownloadFeature.Action")
        #expect(candidate.purity == .effectBearing)
    }

    @Test("closure form continues to match — regression guard for Finding I")
    func closureFormStillMatches() {
        let source = """
        import ComposableArchitecture

        struct Inbox: Reducer {
            struct State {}
            enum Action {}
            var body: some ReducerOf<Self> {
                Reduce { state, action in
                    return .none
                }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .tca)
        #expect(result[0].signatureShape == .inoutStateActionReturnsEffect)
    }

    @Test("Reduce(.enumCase) does not false-trigger")
    func enumCaseSugarRejected() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Foo {
            struct State {}
            enum Action {}
            var body: some ReducerOf<Self> {
                Reduce(.someCase)
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Foo.swift")
        // .someCase is a MemberAccessExpr, not a bare DeclReferenceExpr — reject.
        #expect(result.isEmpty)
    }

    @Test("Reduce(self.handle) member access does not false-trigger")
    func memberAccessRejected() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Bar {
            struct State {}
            enum Action {}
            var body: some ReducerOf<Self> {
                Reduce(self.handle)
            }
            private func handle(into state: inout State, action: Action) -> Effect<Action> { .none }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Bar.swift")
        // self.handle is a MemberAccessExpr — out of scope for this cycle.
        // If real-world data surfaces this pattern, extend in a follow-up.
        #expect(result.isEmpty)
    }

    @Test("Reduce(into:action:) two-closure form does not false-trigger")
    func twoClosureFormRejected() {
        let source = """
        import ComposableArchitecture

        struct Old: Reducer {
            struct State {}
            enum Action {}
            var body: some ReducerOf<Self> {
                Reduce(into: { _, _ in }, action: { _ in .none })
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Old.swift")
        // Two labeled arguments — out of scope (pre-1.0 TCA shape).
        #expect(result.isEmpty)
    }

    @Test("composed body — BindingReducer + Reduce(reduce) — emits one candidate")
    func composedBodyMatches() {
        let source = """
        import ComposableArchitecture

        @Reducer
        public struct ModelDownloadFeature {
            public struct State {}
            public enum Action {}
            public var body: some ReducerOf<Self> {
                BindingReducer()
                Reduce(reduce)
            }
            private func reduce(into state: inout State, action: Action) -> Effect<Action> { .none }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "ModelDownloadFeature.swift")
        // BindingReducer() is a separate FunctionCallExpr with callee
        // "BindingReducer", not "Reduce" — should be ignored. Only the
        // Reduce(reduce) call should emit a candidate.
        #expect(result.count == 1)
    }

    @Test("Reduce(reduce) inside Scope is still found (composition walks past)")
    func methodRefInsideScope() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Parent {
            struct State {}
            enum Action {}
            var body: some ReducerOf<Self> {
                Scope(state: \\.child, action: \\.child) {
                    Reduce(handleChild)
                }
            }
            private func handleChild(into state: inout State, action: Action) -> Effect<Action> { .none }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Parent.swift")
        #expect(result.count == 1)
        #expect(result[0].enclosingTypeName == "Parent")
    }

    @Test("public struct with @Reducer + method-ref body — full Hex regression")
    func publicStructWithMethodRef() {
        let source = """
        import ComposableArchitecture

        @Reducer
        public struct ModelDownloadFeature {
            public struct State { var foo: Int = 0 }
            public enum Action { case binding }
            public var body: some ReducerOf<Self> {
                BindingReducer()
                Reduce(reduce)
            }
            private func reduce(into state: inout State, action: Action) -> Effect<Action> {
                return .none
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "ModelDownloadFeature.swift")
        // The exact public-struct-+-method-ref pattern that v1.110's
        // discover-reducers missed on Hex's ModelDownloadFeature.
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .tca)
    }
}
