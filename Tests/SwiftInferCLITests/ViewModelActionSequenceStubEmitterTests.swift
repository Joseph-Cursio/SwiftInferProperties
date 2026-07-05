@testable import SwiftInferCLI
import SwiftInferCore
import Testing

private func vmAction(
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

/// PROTOTYPE — the M1′ multi-step ViewModel interaction verifier emitter
/// (Observable Carrier thread 1, Slice 3). Materializes the action enum +
/// `drive`, then drives kit-generated `[Action]` sequences against a fresh
/// live probe per trial.
@Suite("ViewModelActionSequenceStubEmitter (prototype)")
struct ViewModelActionSequenceStubEmitterTests {

    private static let predicate =
        "probe.selectedIDs.isSubset(of: Set(probe.items.map { $0.id }))"

    private static func nullaryInputs() -> ViewModelActionSequenceStubEmitter.Inputs {
        .init(
            typeName: "SelectionModel",
            userModuleName: "AppCore",
            predicate: predicate,
            actions: [vmAction("selectAll"), vmAction("deselectAll")]
        )
    }

    @Test("emits enum + drive + kit sequence loop with fresh probe per trial")
    func emitsMultiStepVerifier() throws {
        let source = try ViewModelActionSequenceStubEmitter.emit(Self.nullaryInputs())

        // Kit-backed sequence generation over the synthesized CaseIterable enum.
        #expect(source.contains("import Foundation")) // exit(_:) lives here
        #expect(source.contains("import PropertyBased"))
        #expect(source.contains("import PropertyLawKit"))
        #expect(source.contains("enum SelectionModelAction: CaseIterable, Sendable {"))
        #expect(source.contains("case selectAll"))
        #expect(source.contains(
            "func drive(_ model: SelectionModel, _ action: SelectionModelAction) {"
        ))
        #expect(source.contains("let generator = ActionSequenceFactory.actionSequence("))
        #expect(source.contains("forCaseIterable: SelectionModelAction.self,"))

        // Fresh live probe per trial, replay prefix, per-step re-check.
        #expect(source.contains("let probe = SelectionModel()"))
        #expect(source.contains("drive(probe, action)"))
        #expect(source.contains(Self.predicate))

        // Marker contract (VerifyResult): default multi-step pass/fail.
        #expect(source.contains("@main"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
    }

    @Test("payloaded surface is rejected (deferred to Slice 3b)")
    func rejectsPayloadedSurface() {
        let inputs = ViewModelActionSequenceStubEmitter.Inputs(
            typeName: "CartModel",
            userModuleName: "AppCore",
            predicate: "true",
            actions: [
                vmAction("clear"),
                vmAction("add", [.init(label: nil, typeText: "Item")])
            ]
        )
        #expect(throws: ViewModelActionSequenceStubEmitter.EmitError.self) {
            try ViewModelActionSequenceStubEmitter.emit(inputs)
        }
    }

    @Test("no liftable actions is rejected")
    func rejectsEmptySurface() {
        let inputs = ViewModelActionSequenceStubEmitter.Inputs(
            typeName: "LoaderModel",
            userModuleName: "AppCore",
            predicate: "true",
            actions: [vmAction("load", isAsync: true)]
        )
        #expect(throws: ViewModelActionSequenceStubEmitter.EmitError.self) {
            try ViewModelActionSequenceStubEmitter.emit(inputs)
        }
    }

    @Test("excluded (async/throws) actions are disclosed in the header")
    func disclosesExcludedActions() throws {
        let inputs = ViewModelActionSequenceStubEmitter.Inputs(
            typeName: "SelectionModel",
            userModuleName: "AppCore",
            predicate: Self.predicate,
            actions: [vmAction("selectAll"), vmAction("refresh", isAsync: true)]
        )
        let source = try ViewModelActionSequenceStubEmitter.emit(inputs)
        #expect(source.contains("Excluded from the action surface: refresh (async)"))
    }

    @Test("emission is deterministic (byte-stable seed) for a given type")
    func deterministicOutput() throws {
        let first = try ViewModelActionSequenceStubEmitter.emit(Self.nullaryInputs())
        let second = try ViewModelActionSequenceStubEmitter.emit(Self.nullaryInputs())
        #expect(first == second)
    }
}
