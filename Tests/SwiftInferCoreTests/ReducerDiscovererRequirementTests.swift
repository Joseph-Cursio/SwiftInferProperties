import Foundation
@testable import SwiftInferCore
import Testing

// A function declared in a protocol body is a requirement: a signature with no
// body, so not a reducer. Discovery never pushes a protocol onto its type
// stack, so a requirement read as a free function and was labelled
// `.elmStyle` (found 2026-10-10 by `discover-reducers --target PropertyLawKit`
// in SwiftPropertyLaws: `Ring.add`, `Ring.multiply` and `Semigroup.combine`
// each drew `determinism` and `unknown-action-is-no-op` candidates).

@Suite("ReducerDiscoverer — protocol requirements")
struct ReducerDiscovererRequirementTests {

    private func discover(_ source: String) -> [ReducerCandidate] {
        ReducerDiscoverer.discover(source: source, file: "R.swift")
    }

    @Test("the 2026-10-10 witnesses: a `(Self, Self) -> Self` requirement is not a reducer")
    func requirementIsNotACandidate() {
        let result = discover("""
        public protocol Semigroup {
            static func combine(_ lhs: Self, _ rhs: Self) -> Self
        }
        public protocol Ring {
            static func add(_ lhs: Self, _ rhs: Self) -> Self
            static func multiply(_ lhs: Self, _ rhs: Self) -> Self
        }
        """)
        #expect(result.isEmpty)
    }

    @Test("a protocol-extension method with a body is unchanged")
    func extensionMethodIsStillACandidate() throws {
        let result = discover("""
        public protocol Semigroup {
            static func combine(_ lhs: Self, _ rhs: Self) -> Self
        }
        extension Semigroup {
            static func combine(_ lhs: Self, _ rhs: Self) -> Self { lhs }
        }
        """)
        try #require(result.count == 1)
        #expect(result[0].location == "R.swift:5")
        #expect(result[0].qualifiedName == "Semigroup.combine")
        #expect(result[0].signatureShape == .stateActionReturnsState)
        #expect(result[0].carrierKind == .generic)
    }

    @Test("the skip covers `#if` and a nested protocol, and ends at the protocol's closing brace")
    func skipEndsWithTheProtocolBody() {
        let result = discover("""
        struct AppState: Equatable { var count = 0 }
        enum AppAction { case tap }
        struct Feature {
            protocol Reducing {
                func reduce(_ state: AppState, _ action: AppAction) -> AppState
            }
            static func step(_ state: AppState, _ action: AppAction) -> AppState { state }
        }
        protocol Reducing {
            #if DEBUG
            func reduce(_ state: AppState, _ action: AppAction) -> AppState
            #endif
        }
        func reduce(_ state: AppState, _ action: AppAction) -> AppState { state }
        """)
        #expect(result.map(\.location) == ["R.swift:7", "R.swift:14"])
        #expect(result.map(\.qualifiedName) == ["Feature.step", "reduce"])
        #expect(result.last?.carrierKind == .elmStyle)
    }

    @Test("the protocol is still recorded: a reducer over it resolves `.protocol`")
    func protocolIsStillRecorded() throws {
        let result = discover("""
        struct AppState: Equatable { var count = 0 }
        protocol AppAction {
            func apply(_ state: AppState, _ action: AppAction) -> AppState
        }
        func reduce(_ state: AppState, _ action: AppAction) -> AppState { state }
        """)
        try #require(result.count == 1)
        #expect(result[0].qualifiedName == "reduce")
        #expect(result[0].actionTypeKind == .protocol)
    }
}
