import SwiftEffectInference
@testable import SwiftInferCore
import Testing

/// Phase 0 — proves `ReducerCandidate` and `ViewModelCandidate` lift faithfully
/// onto the unified `StatefulRole` via `asStatefulRole()`. This is the
/// isomorphism the `StatefulRoleDiscoverer` design rests on.
@Suite("StatefulRole adapters")
struct StatefulRoleAdapterTests {

    // MARK: - ViewModel → StatefulRole

    @Test("An @Observable view model lifts onto an mvvm StatefulRole")
    func viewModelLifts() {
        let candidate = ViewModelCandidate(
            location: "Inspector.swift:12",
            typeName: "InspectorViewModel",
            observability: .observableMacro,
            stateFields: [
                ViewModelStateField(name: "selectedId", typeText: "UUID?", isMutable: true),
                ViewModelStateField(name: "title", typeText: "String", isMutable: false)
            ],
            actions: [
                ViewModelAction(
                    name: "select",
                    parameterTypes: ["UUID"],
                    firstParameterLabel: "id",
                    isAsync: false,
                    isThrows: false,
                    mutatesStateDirectly: true
                )
            ],
            constructibility: .zeroArgument,
            initParameters: [ViewModelInitParameter(label: "service", typeText: "any DataService")]
        )

        let role = candidate.asStatefulRole()

        #expect(role.paradigm == .mvvm)
        #expect(role.recognizedBy == .macro)
        #expect(role.typeName == "InspectorViewModel")
        #expect(role.location == "Inspector.swift:12")
        #expect(role.state == .storedFields([
            RoleStateField(name: "selectedId", typeText: "UUID?", isMutable: true),
            RoleStateField(name: "title", typeText: "String", isMutable: false)
        ]))
        #expect(role.actions == [
            RoleAction(
                name: "select",
                parameterTypes: ["UUID"],
                firstParameterLabel: "id",
                mutatesStateDirectly: true
            )
        ])
        #expect(role.construction == .instance(
            initParameters: [RoleInitParameter(label: "service", typeText: "any DataService")],
            fakedCollaborators: []
        ))
        #expect(role.effect == nil)
    }

    @Test("ObservableObject conformance maps recognizedBy to .conformance")
    func observableObjectRecognition() {
        let candidate = ViewModelCandidate(
            location: "VM.swift:1",
            typeName: "LegacyVM",
            observability: .observableObject,
            stateFields: [],
            actions: []
        )
        #expect(candidate.asStatefulRole().recognizedBy == .conformance)
    }

    // MARK: - Reducer → StatefulRole

    @Test("A TCA reducer lifts onto a tca StatefulRole as a free function")
    func tcaReducerLifts() {
        let candidate = ReducerCandidate(
            location: "Feature.swift:8",
            enclosingTypeName: "CounterFeature",
            functionName: "reduce",
            signatureShape: .stateActionReturnsState,
            stateTypeName: "State",
            actionTypeName: "Action",
            carrierKind: .tca,
            purity: .pure,
            actionCases: [
                ActionCaseInfo(name: "increment"),
                ActionCaseInfo(name: "setValue", payloadTypes: ["Int"])
            ]
        )

        let role = candidate.asStatefulRole()

        #expect(role.paradigm == .tca)
        #expect(role.recognizedBy == .conformance)
        #expect(role.typeName == "CounterFeature")
        #expect(role.state == .namedType("State"))
        #expect(role.construction == .freeFunction(name: "reduce"))
        #expect(role.actions == [
            RoleAction(name: "increment", parameterTypes: []),
            RoleAction(name: "setValue", parameterTypes: ["Int"])
        ])
        // ReducerPurity.pure is NOT Effect.pure — left unknown (sound).
        #expect(role.effect == nil)
    }

    @Test("ReSwift/Elm carrier kinds fold into the redux paradigm")
    func reduxFamilyMapsToRedux() {
        for carrier in [ReducerCarrierKind.elmStyle, .reSwift, .mobius, .workflow, .generic] {
            let candidate = ReducerCandidate(
                location: "R.swift:1",
                enclosingTypeName: nil,
                functionName: "appReducer",
                signatureShape: .stateActionReturnsState,
                stateTypeName: "AppState",
                actionTypeName: "AppAction",
                carrierKind: carrier
            )
            let role = candidate.asStatefulRole()
            #expect(role.paradigm == .redux)
            #expect(role.recognizedBy == .signatureShape)
            #expect(role.typeName == "appReducer")   // free function → uses functionName
        }
    }

    @Test("Effectful / hidden-mutability reducers map soundly to nonIdempotent")
    func impureReducersMapToNonIdempotent() {
        for purity in [ReducerPurity.effectBearing, .hiddenMutability] {
            let candidate = ReducerCandidate(
                location: "R.swift:1",
                enclosingTypeName: nil,
                functionName: "reduce",
                signatureShape: .stateActionReturnsState,
                stateTypeName: "S",
                actionTypeName: "A",
                purity: purity
            )
            #expect(candidate.asStatefulRole().effect == .nonIdempotent)
        }
    }
}
