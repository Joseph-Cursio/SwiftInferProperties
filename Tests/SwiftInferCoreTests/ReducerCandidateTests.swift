import Foundation
import Testing
@testable import SwiftInferCore

// V2.0 M1.A — data-model tests for the ReducerCandidate value type
// and its companion ReducerSignatureShape enum. Pure: no SwiftSyntax.

@Suite("ReducerCandidate — V2.0 M1.A data model")
struct ReducerCandidateTests {

    private func candidate(
        location: String = "Sources/Test/F.swift:1",
        enclosingTypeName: String? = nil,
        functionName: String = "reduce",
        signatureShape: ReducerSignatureShape = .stateActionReturnsState,
        stateTypeName: String = "S",
        actionTypeName: String = "A"
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: location,
            enclosingTypeName: enclosingTypeName,
            functionName: functionName,
            signatureShape: signatureShape,
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName
        )
    }

    // MARK: - qualifiedName

    @Test("qualifiedName prepends the enclosing type when present")
    func qualifiedNameWithEnclosingType() {
        let target = candidate(enclosingTypeName: "Inbox", functionName: "reduce")
        #expect(target.qualifiedName == "Inbox.reduce")
    }

    @Test("qualifiedName is just the function name for free functions")
    func qualifiedNameWithoutEnclosingType() {
        let target = candidate(enclosingTypeName: nil, functionName: "reduce")
        #expect(target.qualifiedName == "reduce")
    }

    // MARK: - Signature-shape raw values

    @Test("signature-shape rawValues are stable strings — downstream pipelines key on them")
    func signatureShapeRawValues() {
        #expect(ReducerSignatureShape.stateActionReturnsState.rawValue == "state-action-returns-state")
        #expect(
            ReducerSignatureShape.inoutStateActionReturnsVoid.rawValue
                == "inout-state-action-returns-void"
        )
        #expect(
            ReducerSignatureShape.stateActionReturnsStateAndEffect.rawValue
                == "state-action-returns-state-and-effect"
        )
        #expect(ReducerSignatureShape.allCases.count == 3)
    }

    // MARK: - Codable round-trip

    @Test("ReducerCandidate round-trips through JSONEncoder / JSONDecoder")
    func codableRoundTrip() throws {
        let original = candidate(
            location: "Sources/MyApp/Inbox.swift:42",
            enclosingTypeName: "Inbox",
            functionName: "reduce",
            signatureShape: .inoutStateActionReturnsVoid,
            stateTypeName: "Inbox.State",
            actionTypeName: "Inbox.Action"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReducerCandidate.self, from: data)
        #expect(decoded == original)
    }

    @Test("nil enclosingTypeName round-trips")
    func codableRoundTripFreeFunction() throws {
        let original = candidate(enclosingTypeName: nil, functionName: "update")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReducerCandidate.self, from: data)
        #expect(decoded == original)
        #expect(decoded.enclosingTypeName == nil)
    }
}
