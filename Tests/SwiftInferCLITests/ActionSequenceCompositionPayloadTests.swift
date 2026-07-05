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

    @Test("Result<_, any Error> payload → Gen.always(.case(.failure(CancellationError())))")
    func resultPayloadEmitsFailure() {
        // Type-erased error forms are constructible with a canned error.
        for errorForm in ["Result<String, any Error>", "Result<Int, Error>"] {
            let expr = ActionSequenceStubEmitter.compositionGenerator(
                for: ActionCaseInfo(name: "response", payloadTypes: [errorForm]),
                action: "Feature.Action"
            )
            #expect(expr == "Gen.always(Feature.Action.response(.failure(CancellationError())))")
        }
        // A concrete error type is NOT constructible with CancellationError().
        #expect(
            ActionSequenceStubEmitter.compositionGenerator(
                for: ActionCaseInfo(name: "response", payloadTypes: ["Result<String, MyError>"]),
                action: "Feature.Action"
            ) == nil
        )
    }

    @Test("a resolved IdentifiedActionOf element → Gen.always(.case(.element(id:action:)))")
    func identifiedActionElementEmits() {
        // UUID id → canned zero-UUID literal (slice 3, 3b).
        let uuidCase = ActionCaseInfo(
            name: "rows",
            payloadTypes: ["IdentifiedActionOf<Row>"],
            resolvedElement: ResolvedIdentifiedElement(
                idType: "UUID",
                childActionValue: "Row.Action.increment"
            )
        )
        #expect(
            ActionSequenceStubEmitter.compositionGenerator(for: uuidCase, action: "Feature.Action")
                == "Gen.always(Feature.Action.rows(.element(id: "
                + "UUID(uuidString: \"00000000-0000-0000-0000-000000000000\")!, "
                + "action: Row.Action.increment)))"
        )
        // Int id → 0.
        let intCase = ActionCaseInfo(
            name: "rows",
            payloadTypes: ["IdentifiedActionOf<Row>"],
            resolvedElement: ResolvedIdentifiedElement(
                idType: "Int",
                childActionValue: "Row.Action.tap"
            )
        )
        #expect(
            ActionSequenceStubEmitter.compositionGenerator(for: intCase, action: "Feature.Action")
                == "Gen.always(Feature.Action.rows(.element(id: 0, action: Row.Action.tap)))"
        )
        // String id → "".
        let stringCase = ActionCaseInfo(
            name: "rows",
            payloadTypes: ["IdentifiedActionOf<Row>"],
            resolvedElement: ResolvedIdentifiedElement(
                idType: "String",
                childActionValue: "Row.Action.tap"
            )
        )
        #expect(
            ActionSequenceStubEmitter.compositionGenerator(for: stringCase, action: "Feature.Action")
                == "Gen.always(Feature.Action.rows(.element(id: \"\", action: Row.Action.tap)))"
        )
    }

    @Test("a resolved binding case → .binding(.set(\\.field, value)) per defaultable field")
    func bindingActionEmits() {
        // Single field → Gen.always.
        let single = ActionCaseInfo(
            name: "binding",
            payloadTypes: ["BindingAction<State>"],
            resolvedBinding: [ResolvedBindingField(fieldName: "text", valueType: "String")]
        )
        #expect(
            ActionSequenceStubEmitter.compositionGenerator(for: single, action: "Form.Action")
                == "Gen.always(Form.Action.binding(.set(\\.text, \"\")))"
        )
        // Several fields → Gen.oneOf over each, with type-specific literals.
        let multi = ActionCaseInfo(
            name: "binding",
            payloadTypes: ["BindingAction<State>"],
            resolvedBinding: [
                ResolvedBindingField(fieldName: "flag", valueType: "Bool"),
                ResolvedBindingField(fieldName: "count", valueType: "Int"),
                ResolvedBindingField(fieldName: "ratio", valueType: "Double")
            ]
        )
        #expect(
            ActionSequenceStubEmitter.compositionGenerator(for: multi, action: "Form.Action")
                == "Gen.oneOf(Gen.always(Form.Action.binding(.set(\\.flag, false))), "
                + "Gen.always(Form.Action.binding(.set(\\.count, 0))), "
                + "Gen.always(Form.Action.binding(.set(\\.ratio, 0))))"
        )
    }

    @Test("widened value types: Optional → nil, collection → [] / [:], sized int / Float → 0")
    func bindingActionWidenedTypes() {
        let widened = ActionSequenceStubEmitter.compositionGenerator(
            for: ActionCaseInfo(
                name: "binding",
                payloadTypes: ["BindingAction<State>"],
                resolvedBinding: [
                    ResolvedBindingField(fieldName: "note", valueType: "String?"),
                    ResolvedBindingField(fieldName: "tags", valueType: "[String]"),
                    ResolvedBindingField(fieldName: "attrs", valueType: "[String: Int]"),
                    ResolvedBindingField(fieldName: "big", valueType: "Int64"),
                    ResolvedBindingField(fieldName: "ratio", valueType: "Float")
                ]
            ),
            action: "Form.Action"
        )
        #expect(
            widened == "Gen.oneOf("
                + "Gen.always(Form.Action.binding(.set(\\.note, nil))), "
                + "Gen.always(Form.Action.binding(.set(\\.tags, []))), "
                + "Gen.always(Form.Action.binding(.set(\\.attrs, [:]))), "
                + "Gen.always(Form.Action.binding(.set(\\.big, 0))), "
                + "Gen.always(Form.Action.binding(.set(\\.ratio, 0))))"
        )
        // A custom (non-defaultable) field is dropped from the explored set.
        let mixed = ActionSequenceStubEmitter.compositionGenerator(
            for: ActionCaseInfo(
                name: "binding",
                payloadTypes: ["BindingAction<State>"],
                resolvedBinding: [
                    ResolvedBindingField(fieldName: "custom", valueType: "MyStruct"),
                    ResolvedBindingField(fieldName: "text", valueType: "String")
                ]
            ),
            action: "Form.Action"
        )
        #expect(mixed == "Gen.always(Form.Action.binding(.set(\\.text, \"\")))")
    }

    @Test("an unresolved BindingAction payload is not constructible (excluded)")
    func unresolvedBindingExcluded() {
        #expect(
            ActionSequenceStubEmitter.compositionGenerator(
                for: ActionCaseInfo(name: "binding", payloadTypes: ["BindingAction<State>"]),
                action: "Form.Action"
            ) == nil
        )
    }

    @Test("an unresolved IdentifiedActionOf payload is not constructible (excluded)")
    func unresolvedIdentifiedActionExcluded() {
        // Without a resolvedElement (the resolver gated the child), the raw
        // IdentifiedActionOf<Child> payload is not a recognized wrapper.
        #expect(
            ActionSequenceStubEmitter.compositionGenerator(
                for: ActionCaseInfo(name: "rows", payloadTypes: ["IdentifiedActionOf<Row>"]),
                action: "Feature.Action"
            ) == nil
        )
    }

    @Test("a resolved rows case is constructible and no longer excluded")
    func resolvedRowsCaseConstructible() {
        let reducer = candidate([
            ActionCaseInfo(name: "addButtonTapped"),
            ActionCaseInfo(
                name: "rows",
                payloadTypes: ["IdentifiedActionOf<Row>"],
                resolvedElement: ResolvedIdentifiedElement(
                    idType: "UUID",
                    childActionValue: "Row.Action.increment"
                )
            )
        ])
        let constructible = Set(ActionSequenceStubEmitter.constructibleCases(reducer).map(\.name))
        #expect(constructible.contains("rows"))
        #expect(ActionSequenceStubEmitter.excludedCaseNames(reducer).contains("rows") == false)
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
