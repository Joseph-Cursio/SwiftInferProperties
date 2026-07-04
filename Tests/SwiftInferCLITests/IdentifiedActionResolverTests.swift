import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Item 2 slice 3 — resolving a parent `.tca` reducer's
/// `IdentifiedActionOf<Child>` Action case against the discovered child
/// reducers. Recount-driven: only the `IdentifiedActionOf<Child>` spelling,
/// only a cheaply-defaultable child `State.ID` + a payload-free child case.
@Suite("IdentifiedActionResolver — slice 3 child resolution")
struct IdentifiedActionResolverTests {

    private func child(
        _ name: String,
        idType: String?,
        cases: [ActionCaseInfo]
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/App/\(name).swift:1",
            enclosingTypeName: name,
            functionName: "body",
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: "\(name).State",
            actionTypeName: "\(name).Action",
            carrierKind: .tca,
            actionCases: cases,
            stateIDTypeName: idType
        )
    }

    private func parent(_ payload: String, childCandidates: [ReducerCandidate]) -> ReducerCandidate {
        let parent = ReducerCandidate(
            location: "Sources/App/Parent.swift:1",
            enclosingTypeName: "Parent",
            functionName: "body",
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: "Parent.State",
            actionTypeName: "Parent.Action",
            carrierKind: .tca,
            actionCases: [
                ActionCaseInfo(name: "addButtonTapped"),
                ActionCaseInfo(name: "rows", payloadTypes: [payload])
            ]
        )
        _ = childCandidates
        return parent
    }

    // MARK: - child-name extraction

    @Test("IdentifiedActionOf<Child> extracts the child; other forms are nil")
    func childExtraction() {
        #expect(IdentifiedActionResolver.identifiedActionChild("IdentifiedActionOf<Row>") == "Row")
        #expect(
            IdentifiedActionResolver.identifiedActionChild("IdentifiedActionOf<ObservableBasicsView.Feature>")
                == "ObservableBasicsView.Feature"
        )
        // Spelled-out form is deliberately not resolved (recount: 0 real).
        #expect(IdentifiedActionResolver.identifiedActionChild("IdentifiedAction<UUID, Row.Action>") == nil)
        #expect(IdentifiedActionResolver.identifiedActionChild("PresentationAction<Alert>") == nil)
        #expect(IdentifiedActionResolver.identifiedActionChild("Row") == nil)
    }

    // MARK: - resolution success

    @Test("a UUID-id child with a payload-free case resolves the parent's rows case")
    func resolvesUUIDChild() {
        let row = child("Row", idType: "UUID", cases: [
            ActionCaseInfo(name: "increment"),
            ActionCaseInfo(name: "setText", payloadTypes: ["String"])
        ])
        let enriched = IdentifiedActionResolver.resolve(
            parent("IdentifiedActionOf<Row>", childCandidates: [row]),
            among: [row]
        )
        let rows = enriched.actionCases.first { $0.name == "rows" }
        let element = try? #require(rows?.resolvedElement)
        #expect(element?.idType == "UUID")
        #expect(element?.childActionType == "Row.Action")
        // First payload-free case, depth 0.
        #expect(element?.childActionCase == "increment")
        // The non-composition case is untouched.
        #expect(enriched.actionCases.first { $0.name == "addButtonTapped" }?.resolvedElement == nil)
    }

    @Test("Int / String ids also resolve (folded in for free)")
    func resolvesScalarIds() {
        for idType in ["Int", "String"] {
            let row = child("Row", idType: idType, cases: [ActionCaseInfo(name: "tap")])
            let enriched = IdentifiedActionResolver.resolve(
                parent("IdentifiedActionOf<Row>", childCandidates: [row]),
                among: [row]
            )
            #expect(enriched.actionCases.first { $0.name == "rows" }?.resolvedElement?.idType == idType)
        }
    }

    @Test("a nested-child spelling resolves by last path component")
    func resolvesNestedChildByLastComponent() {
        let feature = child("Feature", idType: "UUID", cases: [ActionCaseInfo(name: "tap")])
        let enriched = IdentifiedActionResolver.resolve(
            parent("IdentifiedActionOf<Observable.Feature>", childCandidates: [feature]),
            among: [feature]
        )
        #expect(enriched.actionCases.first { $0.name == "rows" }?.resolvedElement != nil)
    }

    // MARK: - gates (stays excluded)

    @Test("a custom (non-defaultable) id gates — no resolution")
    func customIdGates() {
        let row = child("Row", idType: "URL", cases: [ActionCaseInfo(name: "tap")])
        let enriched = IdentifiedActionResolver.resolve(
            parent("IdentifiedActionOf<Row>", childCandidates: [row]),
            among: [row]
        )
        #expect(enriched.actionCases.first { $0.name == "rows" }?.resolvedElement == nil)
    }

    @Test("a child with no payload-free case gates (e.g. only BindingAction)")
    func noPayloadFreeChildGates() {
        let todo = child("Todo", idType: "UUID", cases: [
            ActionCaseInfo(name: "binding", payloadTypes: ["BindingAction<Todo.State>"])
        ])
        let enriched = IdentifiedActionResolver.resolve(
            parent("IdentifiedActionOf<Todo>", childCandidates: [todo]),
            among: [todo]
        )
        #expect(enriched.actionCases.first { $0.name == "rows" }?.resolvedElement == nil)
    }

    @Test("an unresolvable child (not discovered) gates")
    func unknownChildGates() {
        let enriched = IdentifiedActionResolver.resolve(
            parent("IdentifiedActionOf<Ghost>", childCandidates: []),
            among: []
        )
        #expect(enriched.actionCases.first { $0.name == "rows" }?.resolvedElement == nil)
    }

    @Test("a child with a nil captured State.ID gates")
    func missingIDTypeGates() {
        let row = child("Row", idType: nil, cases: [ActionCaseInfo(name: "tap")])
        let enriched = IdentifiedActionResolver.resolve(
            parent("IdentifiedActionOf<Row>", childCandidates: [row]),
            among: [row]
        )
        #expect(enriched.actionCases.first { $0.name == "rows" }?.resolvedElement == nil)
    }

    @Test("a non-.tca candidate is returned unchanged")
    func nonTCAUnchanged() {
        var generic = child("Row", idType: "UUID", cases: [ActionCaseInfo(name: "tap")])
        generic = ReducerCandidate(
            location: generic.location,
            enclosingTypeName: generic.enclosingTypeName,
            functionName: generic.functionName,
            signatureShape: .stateActionReturnsState,
            stateTypeName: generic.stateTypeName,
            actionTypeName: generic.actionTypeName,
            carrierKind: .generic,
            actionCases: [ActionCaseInfo(name: "rows", payloadTypes: ["IdentifiedActionOf<Row>"])]
        )
        let enriched = IdentifiedActionResolver.resolve(generic, among: [generic])
        #expect(enriched == generic)
    }
}
