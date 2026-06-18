@testable import SwiftInferCLI
import Testing

/// PROTOTYPE — the ViewModel idempotence verifier stub emitter. Constructs
/// the view model, applies the action, snapshots State, applies it again,
/// and compares — emitting the `VERIFY_*` marker contract `VerifyResultParser`
/// consumes.
@Suite("ViewModelIdempotenceStubEmitter (prototype)")
struct ViewModelIdempotenceStubEmitterTests {

    @Test("emits construct → apply → snapshot → apply → compare with the marker contract")
    func emitsIdempotenceCheck() {
        let source = ViewModelIdempotenceStubEmitter.emit(
            .init(
                typeName: "SelectionModel",
                actionName: "selectAll",
                stateFieldNames: ["selectedIDs", "cursor"]
            )
        )
        #expect(source.contains("let probe = SelectionModel()"))
        // Applied twice with a snapshot between.
        #expect(source.contains("probe.selectAll()"))
        #expect(source.contains("let snapshot_selectedIDs = probe.selectedIDs"))
        #expect(source.contains("let snapshot_cursor = probe.cursor"))
        #expect(source.contains("probe.selectedIDs == snapshot_selectedIDs"))
        #expect(source.contains("probe.cursor == snapshot_cursor"))
        // Marker contract (deterministic → single trial + zero edge sentinel).
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"))
    }

    @Test("no State fields → vacuously-true comparison (still compiles)")
    func emitsVacuousCheckForNoFields() {
        let source = ViewModelIdempotenceStubEmitter.emit(
            .init(typeName: "Empty", actionName: "ping", stateFieldNames: [])
        )
        #expect(source.contains("return true"))
    }

    @Test("single-arg action loops over candidate values, applying the same value twice")
    func emitsXCurriedCheckForArgument() {
        let source = ViewModelIdempotenceStubEmitter.emit(
            .init(
                typeName: "Toggle",
                actionName: "setActive",
                stateFieldNames: ["isActive"],
                argument: .init(typeText: "Bool", label: nil, valuesExpression: "[true, false]")
            )
        )
        #expect(source.contains("for arg in [true, false]"))
        // Fresh state per candidate, applied twice with the SAME arg.
        #expect(source.contains("let probe = Toggle()"))
        #expect(source.contains("probe.setActive(arg)"))
        #expect(source.contains("if !(probe.isActive == snapshot_isActive) { return false }"))
    }

    @Test("labelled single-arg action emits the label at the call site")
    func emitsLabelledCall() {
        let source = ViewModelIdempotenceStubEmitter.emit(
            .init(
                typeName: "Picker",
                actionName: "select",
                stateFieldNames: ["choice"],
                argument: .init(typeText: "Int", label: "index", valuesExpression: "[0, 1]")
            )
        )
        #expect(source.contains("probe.select(index: arg)"))
    }
}
