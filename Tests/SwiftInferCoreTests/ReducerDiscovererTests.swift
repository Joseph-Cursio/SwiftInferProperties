import Foundation
@testable import SwiftInferCore
import Testing

// V2.0 M1.A — SwiftSyntax-pass tests for ReducerDiscoverer. Pure:
// every test passes a string literal of source code and asserts on
// the returned `[ReducerCandidate]`. No disk I/O; no subprocess.

@Suite("ReducerDiscoverer — V2.0 M1.A signature scan")
struct ReducerDiscovererTests {

    // MARK: - Shape 1: (S, A) -> S

    @Test("matches free-function (S, A) -> S")
    func shape1FreeFunction() {
        let source = """
        func reduce(_ state: AppState, _ action: AppAction) -> AppState {
            return state
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        let candidate = result[0]
        #expect(candidate.functionName == "reduce")
        #expect(candidate.signatureShape == .stateActionReturnsState)
        #expect(candidate.stateTypeName == "AppState")
        #expect(candidate.actionTypeName == "AppAction")
        #expect(candidate.enclosingTypeName == nil)
    }

    @Test("matches instance-method (S, A) -> S inside a struct — sets enclosingTypeName")
    func shape1InstanceMethod() {
        let source = """
        struct Inbox {
            func reduce(_ state: State, _ action: Action) -> State { return state }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].enclosingTypeName == "Inbox")
        #expect(result[0].functionName == "reduce")
    }

    @Test("matches static-method (S, A) -> S")
    func shape1StaticMethod() {
        let source = """
        enum Reducer {
            static func reduce(_ state: AppState, _ action: AppAction) -> AppState {
                return state
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].enclosingTypeName == "Reducer")
        #expect(result[0].signatureShape == .stateActionReturnsState)
    }

    // MARK: - Shape 2: (inout S, A) -> Void

    @Test("matches (inout S, A) -> Void")
    func shape2InoutVoidReturn() {
        let source = """
        func reduce(state: inout AppState, action: AppAction) {
            state.count += 1
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].signatureShape == .inoutStateActionReturnsVoid)
        #expect(result[0].stateTypeName == "AppState")
        #expect(result[0].actionTypeName == "AppAction")
    }

    @Test("matches (inout S, A) -> Void with explicit Void return clause")
    func shape2InoutExplicitVoid() {
        let source = """
        func reduce(_ state: inout AppState, _ action: AppAction) -> Void {
            state.count += 1
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].signatureShape == .inoutStateActionReturnsVoid)
    }

    @Test("rejects (inout S, A) -> S — only Void- or Effect-returning inout shapes are canonical")
    func shape2RejectsInoutWithStateReturn() {
        // V1.92 (cycle-89): the `(inout S, A) -> Effect<A>` 4th shape
        // is now a recognized shape, but `(inout S, A) -> S` (return
        // matches first param) remains rejected — no canonical
        // reducer convention returns the same State by value while
        // also taking it inout.
        let source = """
        func reduce(_ state: inout AppState, _ action: AppAction) -> AppState {
            return state
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    // MARK: - Shape 3: (S, A) -> (S, Effect<A>)

    @Test("matches (S, A) -> (S, Effect<A>)")
    func shape3StateEffectTuple() {
        let source = """
        func reduce(_ state: AppState, _ action: AppAction) -> (AppState, Effect<AppAction>) {
            return (state, .none)
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].signatureShape == .stateActionReturnsStateAndEffect)
    }

    @Test("matches (S, A) -> (S, Effect<Combine.Output, Combine.Failure>) — depth-counting comma split")
    func shape3StateEffectWithMultipleGenericArgs() {
        let source = """
        func reduce(_ s: AppState, _ a: AppAction) -> (AppState, Effect<Output, Failure>) {
            return (s, .none)
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].signatureShape == .stateActionReturnsStateAndEffect)
    }

    @Test("rejects tuple-return where second element is not Effect<...>")
    func shape3RejectsNonEffectTuple() {
        let source = """
        func reduce(_ state: AppState, _ action: AppAction) -> (AppState, AppState) {
            return (state, state)
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    // MARK: - Negatives

    @Test("rejects arity-1 dispatch(_:) — naturally implements §2.3 strict-Action-surface")
    func rejectsArity1Dispatch() {
        let source = """
        class AppLogic {
            func dispatch(_ action: AppAction) {}
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    @Test("rejects arity-3 function")
    func rejectsArity3() {
        let source = """
        func reduce(_ s: AppState, _ a: AppAction, _ env: Env) -> AppState {
            return s
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    @Test("rejects (S, A) -> T where T != S")
    func rejectsNonMatchingReturn() {
        let source = """
        func transform(_ s: AppState, _ a: AppAction) -> String {
            return ""
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    @Test("skips private and fileprivate functions — V1.57.A cycle-53 posture carried forward")
    func skipsPrivateAndFileprivate() {
        let source = """
        private func reduce(_ s: AppState, _ a: AppAction) -> AppState { return s }
        fileprivate func update(_ s: AppState, _ a: AppAction) -> AppState { return s }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    @Test("skips generic functions — type-name extraction with placeholders deferred")
    func skipsGenericFunctions() {
        let source = """
        func reduce<S, A>(_ state: S, _ action: A) -> S {
            return state
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    // MARK: - Multi-reducer files

    @Test("multiple reducers in one file all surface")
    func multipleReducersInOneFile() {
        let source = """
        func reduceA(_ s: StateA, _ a: ActionA) -> StateA { return s }
        struct B { func reduce(_ s: StateB, _ a: ActionB) -> StateB { return s } }
        func reduceC(_ s: inout StateC, _ a: ActionC) {}
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 3)
        #expect(Set(result.map(\.functionName)) == ["reduceA", "reduce", "reduceC"])
    }

    @Test("function name is NOT filtered — reducer-ness is signature-only at M1.A")
    func functionNameNotFiltered() {
        let source = """
        func foo(_ s: AppState, _ a: AppAction) -> AppState { return s }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].functionName == "foo")
    }

    // MARK: - Location

    @Test("location records file path and line number")
    func locationCarriesFileAndLine() {
        let source = """
        // line 1
        // line 2
        func reduce(_ s: AppState, _ a: AppAction) -> AppState { return s }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "Inbox.swift")
        #expect(result.count == 1)
        #expect(result[0].location == "Inbox.swift:3")
    }

    // MARK: - V1.C — carrier-kind differentiation

    @Test("V1.C — free `(S, A) -> S` function gets carrierKind: .elmStyle")
    func elmStyleFreeStateActionReturnsState() {
        let source = """
        func reduce(_ s: AppState, _ a: AppAction) -> AppState { return s }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .elmStyle)
    }

    @Test("V1.C — method `(S, A) -> S` on a non-Reducer struct stays .generic")
    func genericMethodStateActionReturnsState() {
        let source = """
        struct Helper {
            func reduce(_ s: AppState, _ a: AppAction) -> AppState { return s }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .generic)
        #expect(result[0].enclosingTypeName == "Helper")
    }

    @Test("V1.C — free `(inout S, A) -> Void` stays .generic — not the Elm idiom")
    func genericFreeInoutShape() {
        let source = """
        func reduce(_ s: inout AppState, _ a: AppAction) {}
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .generic)
    }

    @Test("V1.C — free `(S, A) -> (S, Effect<A>)` stays .generic — TCA-pre-2022 idiom, not Elm")
    func genericFreeEffectTupleShape() {
        let source = """
        func reduce(_ s: AppState, _ a: AppAction) -> (AppState, Effect<AppAction>) {
            return (s, .none)
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .generic)
    }
}

// V2.0 M8.B — body-purity population from `ReducerPurityAnalyzer`.
// Extension-grouped so the main struct stays under SwiftLint's
// type_body_length cap.
extension ReducerDiscovererTests {

    @Test("M8.B — pure body returns purity: .pure")
    func purityPureForCleanBody() {
        let source = """
        func reduce(_ state: AppState, _ action: AppAction) -> AppState {
            return state
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].purity == .pure)
    }

    @Test("M8.B — body with Effect reference returns purity: .effectBearing")
    func purityEffectBearingForEffectReference() {
        let source = """
        func reduce(_ state: AppState, _ action: AppAction) -> (AppState, Effect<AppAction>) {
            return (state, Effect.run { _ in })
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].purity == .effectBearing)
    }

    @Test("M8.B — body that writes to a static var returns purity: .hiddenMutability")
    func purityHiddenMutabilityForStaticWrite() {
        let source = """
        func reduce(_ state: AppState, _ action: AppAction) -> AppState {
            Self.counter += 1
            return state
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].purity == .hiddenMutability)
    }
}

// Container declaration-kind invariance. A reducer whose enclosing type
// holds only static members can be written as a `struct` or as a
// caseless `enum` — the latter is exactly the rewrite SwiftLint's
// `convenience_type` rule prescribes. `ReducerDiscoverer` visits
// `StructDeclSyntax` and `EnumDeclSyntax` identically (same
// `extractTCACandidatesIfReducerConformer` call; the kind is never
// threaded through), so the two forms must yield identical discovery.
//
// This pins the equivalence that lets the v2.0 calibration corpus stay
// frozen: a lint-driven struct→enum rewrite of a `HandRolled` fixture
// would be a no-op for the tool, not a silent baseline shift. It is the
// regression-test counterpart to excluding `Tests/Fixtures` from lint.
extension ReducerDiscovererTests {

    /// The `HandRolled/Hand01_Conservation` fixture shape, parameterized
    /// on the enclosing type's declaration keyword. Line layout is fixed
    /// so the only difference between `struct` and `enum` is the keyword
    /// itself — keeping the recorded `location` line numbers identical.
    private static func conservationReducerSource(container: String) -> String {
        """
        \(container) CountedListReducer {
            struct State {
                var itemCount: Int
                var items: [String]
            }
            enum Action {
                case add(String)
                case noop
            }
            static func reduce(_ state: State, _ action: Action) -> State {
                return state
            }
        }
        """
    }

    @Test("struct vs caseless-enum container yields an identical ReducerCandidate")
    func containerKindInvariantStructVsEnum() {
        let structResult = ReducerDiscoverer.discover(
            source: Self.conservationReducerSource(container: "struct"),
            file: "F.swift"
        )
        let enumResult = ReducerDiscoverer.discover(
            source: Self.conservationReducerSource(container: "enum"),
            file: "F.swift"
        )

        #expect(structResult.count == 1)
        #expect(enumResult.count == 1)
        // `ReducerCandidate` is `Equatable` and the two sources are
        // line-for-line identical apart from the keyword, so a matching
        // candidate is fully ==-equal — `location` included.
        #expect(structResult == enumResult)
        #expect(enumResult.first?.enclosingTypeName == "CountedListReducer")
        #expect(enumResult.first?.functionName == "reduce")
        #expect(enumResult.first?.signatureShape == .stateActionReturnsState)
    }
}
