@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — the synthetic-Action-enum emitter (Observable Carrier
/// thread 1, M1′). Lifts a view model's mutating methods into an
/// `enum <Type>Action` + a `drive(_ model, _ action)` dispatcher.
@Suite("ViewModelActionEnumEmitter (prototype)")
struct ViewModelActionEnumEmitterTests {

    private static func action(
        _ name: String,
        _ parameters: [ViewModelActionParameter] = [],
        isAsync: Bool = false,
        isThrows: Bool = false
    ) -> ViewModelAction {
        ViewModelAction(
            name: name,
            parameterTypes: parameters.map(\.typeText),
            firstParameterLabel: parameters.first?.label,
            parameters: parameters,
            isAsync: isAsync,
            isThrows: isThrows,
            mutatesStateDirectly: true
        )
    }

    @Test("payloaded model: labelled multi-arg, positional, and nullary cases")
    func payloadShapes() {
        let result = ViewModelActionEnumEmitter.emit(
            typeName: "EditorViewModel",
            actions: [
                Self.action("addTag", [.init(label: nil, typeText: "String")]),
                Self.action("clear"),
                Self.action("rename", [
                    .init(label: "id", typeText: "UUID"),
                    .init(label: "to", typeText: "String")
                ])
            ]
        )

        #expect(result.enumName == "EditorViewModelAction")
        #expect(result.isCaseIterable == false)
        #expect(result.skipped.isEmpty)
        #expect(result.lifted.map(\.caseName) == ["addTag", "clear", "rename"])

        // Enum cases — labels preserved for the multi-arg case.
        #expect(result.source.contains("enum EditorViewModelAction: Sendable {"))
        #expect(result.source.contains("case addTag(String)"))
        #expect(result.source.contains("case clear"))
        #expect(result.source.contains("case rename(id: UUID, to: String)"))

        // Dispatcher — positional bindings, original labels at the call site.
        #expect(result.source.contains(
            "func drive(_ model: EditorViewModel, _ action: EditorViewModelAction) {"
        ))
        #expect(result.source.contains("case .addTag(let a0): model.addTag(a0)"))
        #expect(result.source.contains("case .clear: model.clear()"))
        #expect(result.source.contains(
            "case .rename(let a0, let a1): model.rename(id: a0, to: a1)"
        ))
    }

    @Test("nullary-only model conforms to CaseIterable")
    func nullaryOnlyIsCaseIterable() {
        let result = ViewModelActionEnumEmitter.emit(
            typeName: "CounterModel",
            actions: [Self.action("increment"), Self.action("reset")]
        )
        #expect(result.isCaseIterable == true)
        #expect(result.source.contains("enum CounterModelAction: CaseIterable, Sendable {"))
    }

    @Test("async / throws methods are dropped from the surface with a reason")
    func skipsAsyncAndThrows() {
        let result = ViewModelActionEnumEmitter.emit(
            typeName: "LoaderModel",
            actions: [
                Self.action("reset"),
                Self.action("load", isAsync: true),
                Self.action("save", isThrows: true)
            ]
        )
        #expect(result.lifted.map(\.caseName) == ["reset"])
        #expect(result.skipped == [
            .init(action: "load", reason: .asyncMethod),
            .init(action: "save", reason: .throwingMethod)
        ])
        #expect(!result.source.contains("case load"))
        #expect(!result.source.contains("case save"))
    }

    @Test("overloaded methods get collision-disambiguated case names")
    func disambiguatesOverloads() {
        let result = ViewModelActionEnumEmitter.emit(
            typeName: "PickerModel",
            actions: [
                Self.action("select", [.init(label: nil, typeText: "UUID")]),
                Self.action("select", [.init(label: "all", typeText: "Bool")])
            ]
        )
        // Distinct case names…
        #expect(result.lifted.map(\.caseName) == ["select", "selectAll"])
        #expect(result.source.contains("case select(UUID)"))
        #expect(result.source.contains("case selectAll(all: Bool)"))
        // …but both dispatch to the ORIGINAL method name `select`.
        #expect(result.source.contains("case .select(let a0): model.select(a0)"))
        #expect(result.source.contains("case .selectAll(let a0): model.select(all: a0)"))
    }

    @Test("keyword method name is backtick-escaped in case, pattern, and call")
    func escapesKeywordMethodName() {
        let result = ViewModelActionEnumEmitter.emit(
            typeName: "LoopModel",
            actions: [Self.action("repeat")]
        )
        #expect(result.source.contains("case `repeat`"))
        #expect(result.source.contains("case .`repeat`: model.`repeat`()"))
    }
}
