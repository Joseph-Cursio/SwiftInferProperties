import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Item-2 slice 1 — composition-action payloads. Widens Phase B's constructible
/// subset beyond payload-free + raw-scalar cases to recognized TCA composition
/// wrappers the verifier can construct a canonical value for without deriving
/// the wrapped type. Slice 1 is `PresentationAction<T>` → the payload-free
/// `.dismiss` case.
@Suite("ActionSequenceStubEmitter — composition-action payloads (item 2)")
struct ActionSequenceCompositionPayloadTests {

    private func candidate(_ cases: [ActionCaseInfo]) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/App/Feature.swift:1",
            enclosingTypeName: "Feature",
            functionName: "body",
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: "Feature.State",
            actionTypeName: "Feature.Action",
            carrierKind: .tca,
            actionCases: cases
        )
    }

    @Test("PresentationAction payload → Gen.always(.case(.dismiss))")
    func presentationActionEmitsDismiss() {
        let expr = ActionSequenceStubEmitter.compositionGenerator(
            for: ActionCaseInfo(name: "alert", payloadTypes: ["PresentationAction<Alert>"]),
            action: "Feature.Action"
        )
        #expect(expr == "Gen.always(Feature.Action.alert(.dismiss))")
    }

    @Test("a non-wrapper single payload is not a composition case")
    func nonWrapperPayloadIsNil() {
        #expect(
            ActionSequenceStubEmitter.compositionGenerator(
                for: ActionCaseInfo(name: "updated", payloadTypes: ["User"]),
                action: "Feature.Action"
            ) == nil
        )
        // Multi-value payloads are not single-wrapper composition either.
        #expect(
            ActionSequenceStubEmitter.compositionGenerator(
                for: ActionCaseInfo(name: "pair", payloadTypes: ["Int", "String"]),
                action: "Feature.Action"
            ) == nil
        )
    }

    @Test("a presentation case is now constructible and no longer excluded")
    func presentationCaseIsConstructible() {
        let reducer = candidate([
            ActionCaseInfo(name: "tapped"),
            ActionCaseInfo(name: "alert", payloadTypes: ["PresentationAction<Alert>"]),
            ActionCaseInfo(name: "updated", payloadTypes: ["User"])  // still excluded
        ])
        let constructible = Set(ActionSequenceStubEmitter.constructibleCases(reducer).map(\.name))
        #expect(constructible.contains("alert"))
        #expect(constructible.contains("tapped"))
        #expect(constructible.contains("updated") == false)

        let excluded = ActionSequenceStubEmitter.excludedCaseNames(reducer)
        #expect(excluded.contains("alert") == false)
        #expect(excluded.contains("updated"))
    }
}
