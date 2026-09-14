import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The carrier a law quantifies over, and what happens when it is read from the wrong place
/// (#456).
///
/// **`idempotentStub` read its carrier from the first parameter.** A nullary instance method has
/// none, so `shellEscapeForVariableName() -> Self` was proposed and dropped one guard from being
/// written — even though its law is spellable: `applicationArity` for a nullary instance method
/// is 1, exactly what `idempotence` applies, and `call(_:)` has rendered the receiver form since
/// #445.
///
/// **Measured at 245 of 1 230 idempotence suggestions — 19.9% — across 20 corpora.** One in five
/// laws the pipeline proposed could not be written, for a parameter it never needed.
@Suite("Carrier — parameter, else receiver")
struct ReceiverCarrierTests {

    private static func evidence(
        _ displayName: String,
        signature: String,
        carrier: String? = nil
    ) -> Evidence {
        Evidence(
            displayName: displayName,
            signature: signature,
            location: SourceLocation(file: "F.swift", line: 1, column: 1),
            qualifiedTypeName: carrier
        )
    }

    /// Unchanged behaviour: a parameterised subject still takes its carrier from the parameter.
    @Test func aParameterisedSubjectUsesItsParameter() {
        #expect(InteractiveTriage.carrierType(
            for: Self.evidence("strip(_:)", signature: "(String) -> String", carrier: "Formatter")
        ) == "String")
    }

    /// The measured case: no parameter, so the law is over the receiver.
    @Test func aNullaryInstanceMethodUsesItsReceiver() {
        #expect(InteractiveTriage.carrierType(
            for: Self.evidence("shellEscapeForVariableName()", signature: "() -> Self", carrier: "String")
        ) == "String")
    }

    /// **The negative.** A free nullary function has neither, and there is genuinely nothing for
    /// a law to quantify over — inventing a carrier here would emit a stub over a value that
    /// does not exist.
    @Test func aFreeNullaryFunctionHasNoCarrier() {
        #expect(InteractiveTriage.carrierType(
            for: Self.evidence("now()", signature: "() -> Date")
        ) == nil)
    }

    // MARK: - The annotation the receiver form needs to compile

    /// **Not cosmetic.** `{ value in value.htmlEscaped.htmlEscaped == value.htmlEscaped }` gives
    /// the solver nothing to anchor `value` on, and Swift reports *"the compiler is unable to
    /// type-check this expression in reasonable time"*. A call form anchors it for free, which
    /// is why every stub emitted before receiver-form laws existed compiled.
    ///
    /// Measured: the recovered stub fails to build without this and builds with it.
    @Test func theIdempotenceClosureParameterIsAnnotated() {
        let stub = LiftedTestEmitter.idempotent(
            callee: CalleeReference(bareName: "trimmed", isInstanceMethod: true, isComputedProperty: true),
            typeName: "String",
            seed: SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            generator: "Gen<String>.always(\"x\")"
        )
        #expect(stub.contains("property: { (value: String) in"))
    }
}
