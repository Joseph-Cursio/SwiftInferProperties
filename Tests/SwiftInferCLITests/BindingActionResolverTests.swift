import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Item 2 slice 4 — resolving a `.tca` reducer's `binding(BindingAction<State>)`
/// action against its own `@ObservableState` stored fields (defaultable value
/// types only), so the emitter can construct `.set(\.field, value)`.
@Suite("BindingActionResolver — slice 4 binding resolution")
struct BindingActionResolverTests {

    private func candidate(
        cases: [ActionCaseInfo],
        fields: [StateFieldInfo]
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/App/Form.swift:1",
            enclosingTypeName: "Form",
            functionName: "body",
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: "Form.State",
            actionTypeName: "Form.Action",
            carrierKind: .tca,
            actionCases: cases,
            stateFields: fields
        )
    }

    @Test("BindingAction<State> payload is recognized; others are not")
    func payloadRecognition() {
        #expect(BindingActionResolver.isBindingActionPayload("BindingAction<State>"))
        #expect(BindingActionResolver.isBindingActionPayload("BindingAction<Form.State>"))
        #expect(BindingActionResolver.isBindingActionPayload("PresentationAction<Alert>") == false)
        #expect(BindingActionResolver.isBindingActionPayload("Int") == false)
    }

    @Test("binding case resolves to every defaultable stored field")
    func resolvesDefaultableFields() {
        let reducer = candidate(
            cases: [
                ActionCaseInfo(name: "submitTapped"),
                ActionCaseInfo(name: "binding", payloadTypes: ["BindingAction<State>"])
            ],
            fields: [
                StateFieldInfo(name: "text", typeName: "String"),
                StateFieldInfo(name: "flag", typeName: "Bool"),
                StateFieldInfo(name: "count", typeName: "Int")
            ]
        )
        let enriched = BindingActionResolver.resolve(reducer)
        let binding = enriched.actionCases.first { $0.name == "binding" }
        let fields = try? #require(binding?.resolvedBinding)
        #expect(fields?.map(\.fieldName) == ["text", "flag", "count"])
        #expect(fields?.map(\.valueType) == ["String", "Bool", "Int"])
        // Non-binding case untouched.
        #expect(enriched.actionCases.first { $0.name == "submitTapped" }?.resolvedBinding == nil)
    }

    @Test("non-defaultable fields are filtered out")
    func filtersCustomTypes() {
        let enriched = BindingActionResolver.resolve(candidate(
            cases: [ActionCaseInfo(name: "binding", payloadTypes: ["BindingAction<State>"])],
            fields: [
                StateFieldInfo(name: "text", typeName: "String"),
                StateFieldInfo(name: "focus", typeName: "Field?"),
                StateFieldInfo(name: "syncUp", typeName: "SyncUp")
            ]
        ))
        #expect(enriched.actionCases[0].resolvedBinding?.map(\.fieldName) == ["text"])
    }

    // MARK: - gates

    @Test("no bindable (defaultable) field gates — binding stays unresolved")
    func noDefaultableFieldGates() {
        let enriched = BindingActionResolver.resolve(candidate(
            cases: [ActionCaseInfo(name: "binding", payloadTypes: ["BindingAction<State>"])],
            fields: [StateFieldInfo(name: "syncUp", typeName: "SyncUp")]
        ))
        #expect(enriched.actionCases[0].resolvedBinding == nil)
    }

    @Test("empty stateFields (non-observable State) gates")
    func noStateFieldsGates() {
        let enriched = BindingActionResolver.resolve(candidate(
            cases: [ActionCaseInfo(name: "binding", payloadTypes: ["BindingAction<State>"])],
            fields: []
        ))
        #expect(enriched.actionCases[0].resolvedBinding == nil)
    }

    @Test("no binding case → candidate unchanged")
    func noBindingCase() {
        let reducer = candidate(
            cases: [ActionCaseInfo(name: "submitTapped")],
            fields: [StateFieldInfo(name: "text", typeName: "String")]
        )
        #expect(BindingActionResolver.resolve(reducer) == reducer)
    }

    @Test("a non-.tca candidate is returned unchanged")
    func nonTCAUnchanged() {
        let generic = ReducerCandidate(
            location: "x:1",
            enclosingTypeName: "Form",
            functionName: "reduce",
            signatureShape: .stateActionReturnsState,
            stateTypeName: "Form.State",
            actionTypeName: "Form.Action",
            carrierKind: .generic,
            actionCases: [ActionCaseInfo(name: "binding", payloadTypes: ["BindingAction<State>"])],
            stateFields: [StateFieldInfo(name: "text", typeName: "String")]
        )
        #expect(BindingActionResolver.resolve(generic) == generic)
    }
}
