import Foundation
@testable import SwiftInferCore
import Testing

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

    // MARK: - stateQualifiedName / actionQualifiedName (V1.91 cross-contam fix)

    @Test("stateQualifiedName prefixes bare State with enclosing type (M1.A shape)")
    func stateQualifiedNameFromBareName() {
        let target = candidate(enclosingTypeName: "Inbox", stateTypeName: "State")
        #expect(target.stateQualifiedName == "Inbox.State")
    }

    @Test("stateQualifiedName passes already-qualified names through (M1.B shape)")
    func stateQualifiedNamePassesQualifiedThrough() {
        // M1.B's TCA closure walker pre-qualifies as `<enclosing>.State`
        // because the literal text feeds downstream stub-emission shapes
        // like `\(stateTypeName)()`. Double-qualifying would produce
        // `LazyNavigation.LazyNavigation.State` and break detector lookup.
        let target = candidate(enclosingTypeName: "LazyNavigation", stateTypeName: "LazyNavigation.State")
        #expect(target.stateQualifiedName == "LazyNavigation.State")
    }

    @Test("stateQualifiedName is just the bare name for free-function reducers")
    func stateQualifiedNameForFreeFunction() {
        let target = candidate(enclosingTypeName: nil, stateTypeName: "CounterState")
        #expect(target.stateQualifiedName == "CounterState")
    }

    @Test("actionQualifiedName prefixes bare Action with enclosing type (M1.A shape)")
    func actionQualifiedNameFromBareName() {
        let target = candidate(enclosingTypeName: "Inbox", actionTypeName: "Action")
        #expect(target.actionQualifiedName == "Inbox.Action")
    }

    @Test("actionQualifiedName passes already-qualified names through (M1.B shape)")
    func actionQualifiedNamePassesQualifiedThrough() {
        let target = candidate(enclosingTypeName: "LazyNavigation", actionTypeName: "LazyNavigation.Action")
        #expect(target.actionQualifiedName == "LazyNavigation.Action")
    }

    @Test("actionQualifiedName is just the bare name for free-function reducers")
    func actionQualifiedNameForFreeFunction() {
        let target = candidate(enclosingTypeName: nil, actionTypeName: "CounterAction")
        #expect(target.actionQualifiedName == "CounterAction")
    }

    // MARK: - Signature-shape raw values

    @Test("M1.A signature-shape rawValues are stable strings — downstream pipelines key on them")
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
        // The 4th case (inoutStateActionReturnsEffect) is asserted in the
        // V1.B test block below — `allCases.count` is checked there.
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

    // MARK: - V1.B — carrierKind + 4th signature shape

    @Test("carrierKind defaults to .generic — M1.A candidates retroactively keep their kind")
    func carrierKindDefaultsToGeneric() {
        let target = candidate()
        #expect(target.carrierKind == .generic)
    }

    @Test("ReducerCarrierKind rawValues are stable strings")
    func carrierKindRawValues() {
        #expect(ReducerCarrierKind.generic.rawValue == "generic")
        #expect(ReducerCarrierKind.tca.rawValue == "tca")
        #expect(ReducerCarrierKind.elmStyle.rawValue == "elm-style")
        // ReSwift + Mobius + Workflow framework vocabulary.
        #expect(ReducerCarrierKind.reSwift.rawValue == "reswift")
        #expect(ReducerCarrierKind.mobius.rawValue == "mobius")
        #expect(ReducerCarrierKind.workflow.rawValue == "workflow")
        #expect(ReducerCarrierKind.allCases.count == 6)
    }

    @Test("4th ReducerSignatureShape — TCA Reduce closure synthesized signature")
    func tcaSignatureShapeRawValue() {
        #expect(
            ReducerSignatureShape.inoutStateActionReturnsEffect.rawValue
                == "inout-state-action-returns-effect"
        )
        #expect(ReducerSignatureShape.allCases.count == 4)
    }

    @Test("ReducerCandidate round-trips with carrierKind: .tca")
    func codableRoundTripWithTCACarrier() throws {
        let original = ReducerCandidate(
            location: "Sources/MyApp/Inbox.swift:42",
            enclosingTypeName: "Inbox",
            functionName: "body",
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: "Inbox.State",
            actionTypeName: "Inbox.Action",
            carrierKind: .tca
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReducerCandidate.self, from: data)
        #expect(decoded == original)
        #expect(decoded.carrierKind == .tca)
    }

    @Test("ReducerCandidate decodes legacy records missing carrierKind as .generic")
    func codableBackwardCompatMissingCarrierKind() throws {
        // Hand-crafted JSON without the `carrierKind` key — simulates a
        // record persisted before V1.B shipped (none exist on disk yet
        // but the schema is forward-defended).
        let json = """
        {
            "location": "Sources/X.swift:1",
            "functionName": "reduce",
            "signatureShape": "state-action-returns-state",
            "stateTypeName": "S",
            "actionTypeName": "A"
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ReducerCandidate.self, from: data)
        #expect(decoded.carrierKind == .generic)
    }

    // MARK: - V2.0 M8.B — purity field

    @Test("purity defaults to .pure when no body-analyzer signal supplied")
    func purityDefaultsToPure() {
        let target = candidate()
        #expect(target.purity == .pure)
    }

    @Test("ReducerCandidate round-trips with purity: .effectBearing (M8.B)")
    func codableRoundTripWithEffectBearingPurity() throws {
        let original = ReducerCandidate(
            location: "Sources/MyApp/Inbox.swift:42",
            enclosingTypeName: "Inbox",
            functionName: "reduce",
            signatureShape: .stateActionReturnsStateAndEffect,
            stateTypeName: "Inbox.State",
            actionTypeName: "Inbox.Action",
            carrierKind: .generic,
            purity: .effectBearing
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReducerCandidate.self, from: data)
        #expect(decoded == original)
        #expect(decoded.purity == .effectBearing)
    }

    @Test("ReducerCandidate decodes legacy records missing purity as .pure (M8.B back-compat)")
    func codableBackwardCompatMissingPurity() throws {
        let json = """
        {
            "location": "Sources/X.swift:1",
            "functionName": "reduce",
            "signatureShape": "state-action-returns-state",
            "stateTypeName": "S",
            "actionTypeName": "A",
            "carrierKind": "generic"
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ReducerCandidate.self, from: data)
        #expect(decoded.purity == .pure)
    }
}
