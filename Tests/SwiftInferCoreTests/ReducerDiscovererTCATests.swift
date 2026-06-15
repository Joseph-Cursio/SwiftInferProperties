import Foundation
@testable import SwiftInferCore
import Testing

// V2.0 M1.B — TCA-path tests for ReducerDiscoverer. Each test source
// imports ComposableArchitecture (so the conformance walk fires) and
// asserts on the resulting `[ReducerCandidate]`. Pure: no disk I/O.
// Split out of ReducerDiscovererTests.swift to keep both files under
// SwiftLint's `file_length` / `type_body_length` caps as the V1.B
// path landed.

@Suite("ReducerDiscoverer — V2.0 M1.B TCA conformance walk")
struct ReducerDiscovererTCATests {

    @Test("matches Reduce { state, action in ... } inside a Reducer conformer")
    func basicMatch() {
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
        let candidate = result[0]
        #expect(candidate.carrierKind == .tca)
        #expect(candidate.signatureShape == .inoutStateActionReturnsEffect)
        #expect(candidate.enclosingTypeName == "Inbox")
        #expect(candidate.functionName == "body")
        #expect(candidate.stateTypeName == "Inbox.State")
        #expect(candidate.actionTypeName == "Inbox.Action")
    }

    @Test("Cycle 122 — payload-free Action cases captured in source order")
    func capturesPayloadFreeActionCases() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Counter {
            struct State: Equatable { var count = 0 }
            enum Action {
                case increment
                case decrement
                case closeMenu
            }
            var body: some Reducer<State, Action> {
                Reduce { state, action in .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Counter.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .tca)
        // Source order preserved — the verifier's explicit-case generator
        // depends on a stable, complete list.
        #expect(result[0].actionCaseNames == ["increment", "decrement", "closeMenu"])
    }

    @Test("Cycle 122 — any payload case ⇒ empty list (verify-reject, Phase B territory)")
    func payloadCaseSuppressesCapture() {
        let source = """
        import ComposableArchitecture

        @Reducer
        struct Form {
            struct State: Equatable {}
            enum Action {
                case submit
                case setName(String)
            }
            var body: some Reducer<State, Action> {
                Reduce { state, action in .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Form.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .tca)
        // One associated-value case ⇒ the whole list is withheld so the
        // emitter keeps rejecting (no verifying over a partial action space).
        #expect(result[0].actionCaseNames.isEmpty)
    }

    @Test("Reduce match is gated on `import ComposableArchitecture`")
    func requiresComposableArchitectureImport() {
        let source = """
        // No import of ComposableArchitecture — conservative skip.
        struct Inbox: Reducer {
            var body: some ReducerOf<Self> {
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.isEmpty)
    }

    @Test("Reducer conformance generic form (Reducer<State, Action>) recognized")
    func genericReducerConformance() {
        let source = """
        import ComposableArchitecture

        struct Inbox: Reducer<MyState, MyAction> {
            var body: some ReducerOf<Self> {
                Reduce { s, a in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .tca)
    }

    @Test("multiple Reduce closures in one body all surface")
    func multipleReduceClosures() {
        let source = """
        import ComposableArchitecture

        struct Inbox: Reducer {
            var body: some ReducerOf<Self> {
                Reduce { state, action in return .none }
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.carrierKind == .tca })
    }

    @Test("Reduce closures nested under Scope / CombineReducers are still found")
    func reduceNestedInsideScope() {
        let source = """
        import ComposableArchitecture

        struct Parent: Reducer {
            var body: some ReducerOf<Self> {
                Scope(state: \\.child, action: \\.child) {
                    Reduce { s, a in return .none }
                }
                Reduce { s, a in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Parent.swift")
        #expect(result.count == 2)
    }

    @Test("EmptyReducer / BindingReducer alone in body emits nothing")
    func nonReduceCombinatorsEmitNothing() {
        let source = """
        import ComposableArchitecture

        struct Inbox: Reducer {
            var body: some ReducerOf<Self> {
                EmptyReducer()
            }
        }
        struct Form: Reducer {
            var body: some ReducerOf<Self> {
                BindingReducer()
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    @Test("class with Reducer conformance is also recognized")
    func onClass() {
        let source = """
        import ComposableArchitecture

        final class Inbox: Reducer {
            var body: some ReducerOf<Self> {
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.count == 1)
        #expect(result[0].enclosingTypeName == "Inbox")
    }

    @Test("extension Inbox: Reducer with body picks up Reduce closures")
    func extensionConformance() {
        let source = """
        import ComposableArchitecture

        struct Inbox {}
        extension Inbox: Reducer {
            var body: some ReducerOf<Self> {
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.count == 1)
        #expect(result[0].enclosingTypeName == "Inbox")
        #expect(result[0].carrierKind == .tca)
    }

    @Test("Reducer conformance with arity-1 Reduce closure (e.g. { $0 }) is rejected")
    func rejectsWrongArityClosure() {
        let source = """
        import ComposableArchitecture

        struct Inbox: Reducer {
            var body: some ReducerOf<Self> {
                Reduce { state in return state }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.isEmpty)
    }

    @Test("private Reducer conformer is skipped")
    func skipsPrivate() {
        let source = """
        import ComposableArchitecture

        private struct Inbox: Reducer {
            var body: some ReducerOf<Self> {
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.isEmpty)
    }

    @Test("closure parameter names don't matter — shape is positional")
    func closureParameterNameAgnostic() {
        let source = """
        import ComposableArchitecture

        struct Inbox: Reducer {
            var body: some ReducerOf<Self> {
                Reduce { value, msg in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.count == 1)
    }

    @Test("non-Reducer conformer in a TCA-importing file is not touched")
    func ignoresNonReducerType() {
        let source = """
        import ComposableArchitecture

        struct Helper {
            var body: some View {
                Reduce { state, action in return .none }
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Helper.swift")
        #expect(result.isEmpty)
    }
}
