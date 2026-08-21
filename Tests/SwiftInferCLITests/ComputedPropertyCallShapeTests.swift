import Foundation
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

/// **A computed property is accessed, not called.**
///
/// `FunctionSummary.isComputedProperty` is set by `FunctionScannerVisitor+Summary` and carried
/// through `Suggestion`, `SemanticIndexEntry` and `StrategistDispatchEmitter.Inputs`. Until
/// 2026-08-21 exactly **one** consumer read it — `composeSelfReturningInvolutionPass`, whose
/// `let accessor = isComputedProperty ? "" : "()"` is the correct handling — and every other
/// shape emitted `value.description()` for a `public var description`.
///
/// Measured on swift-system @ `6a63f08` (`docs/measurements/criterion-a-swift-system.md` §3):
/// **5 of 6 build failures were this**, every one reading `cannot call value of non-function
/// type`. `FilePath.description`, `.string`, `._portableDescription` and `.dirname` are all
/// `public var`.
///
/// These assert the emitted **text**, not a compile. That is the right granularity here: the
/// defect is a two-character difference in a rendered call, and a fixture package that
/// compiles would prove the same thing far more slowly while making the failure message worse.
/// The compile-level cover already exists — this shape is what made the survey's stubs fail to
/// build, and the survey is the end-to-end check.
@Suite("Computed properties are accessed, not called")
struct ComputedPropertyCallShapeTests {

    private func entry(
        primaryFunctionName: String,
        isComputedProperty: Bool,
        isInstanceMethod: Bool = true
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xDEADBEEF",
            templateName: "idempotence",
            typeName: "FilePath",
            score: 60,
            tier: "Strong",
            primaryFunctionName: primaryFunctionName,
            location: "/tmp/FilePath.swift:1",
            firstSeenAt: "2026-08-21T00:00:00Z",
            lastSeenAt: "2026-08-21T00:00:00Z",
            carrierTypeName: "FilePath",
            isInstanceMethod: isInstanceMethod,
            isComputedProperty: isComputedProperty
        )
    }

    @Test("the receiver closure accesses a computed property")
    func receiverClosureAccessesAProperty() {
        let call = SwiftInferCommand.Verify.receiverCallExpression(
            entry: entry(primaryFunctionName: "dirname", isComputedProperty: true),
            reference: "FilePath.dirname",
            bareFunctionName: "FilePath.dirname"
        )
        #expect(call == "{ $0.dirname }")
    }

    /// The control. A nullary *method* must keep its parens — a fix that dropped them
    /// everywhere would satisfy the arm above and break every instance-method law there is.
    @Test("the receiver closure still calls a nullary method")
    func receiverClosureStillCallsAMethod() {
        let call = SwiftInferCommand.Verify.receiverCallExpression(
            entry: entry(primaryFunctionName: "lexicallyNormalized", isComputedProperty: false),
            reference: "FilePath.lexicallyNormalized",
            bareFunctionName: "FilePath.lexicallyNormalized"
        )
        #expect(call == "{ $0.lexicallyNormalized() }")
    }

    /// A method taking arguments is untouched by either branch, and is the arm that would
    /// catch a gate written on the flag alone.
    @Test("a method with arguments keeps its argument list")
    func aMethodWithArgumentsIsUnchanged() {
        let call = SwiftInferCommand.Verify.receiverCallExpression(
            entry: entry(primaryFunctionName: "pushing(_:)", isComputedProperty: false),
            reference: "FilePath.pushing",
            bareFunctionName: "FilePath.pushing"
        )
        #expect(call == "{ $0.pushing($1) }")
    }

    /// **The flag and the labels must agree.** A "property" carrying an argument list is a
    /// disagreement between two independently-recorded facts, and the emitter declines to
    /// resolve it silently: it keeps the call shape, which is the one that can still compile.
    @Test("a property flag beside an argument list does not drop the arguments")
    func aDisagreementKeepsTheCallShape() {
        let call = SwiftInferCommand.Verify.receiverCallExpression(
            entry: entry(primaryFunctionName: "pushing(_:)", isComputedProperty: true),
            reference: "FilePath.pushing",
            bareFunctionName: "FilePath.pushing"
        )
        #expect(call == "{ $0.pushing($1) }")
    }

    @Test("the self-returning idempotence chain accesses a computed property")
    func idempotenceChainAccessesAProperty() {
        let source = StrategistDispatchEmitter.composeSelfReturningIdempotencePass(
            functionCall: "FilePath.dirname",
            recipe: StrategistDispatchEmitter.GeneratorRecipe(
                expression: "Gen<FilePath>.always(FilePath(\"/a\"))",
                carrierTypeName: "FilePath",
                imports: ["PropertyBased"]
            ),
            isComputedProperty: true
        )
        #expect(source.contains("let onceResult = value.dirname\n"))
        #expect(source.contains("let twiceResult = onceResult.dirname\n"))
        #expect(!source.contains("dirname()"))
    }

    @Test("the self-returning idempotence chain still calls a nullary method")
    func idempotenceChainStillCallsAMethod() {
        let source = StrategistDispatchEmitter.composeSelfReturningIdempotencePass(
            functionCall: "FilePath.lexicallyNormalized",
            recipe: StrategistDispatchEmitter.GeneratorRecipe(
                expression: "Gen<FilePath>.always(FilePath(\"/a\"))",
                carrierTypeName: "FilePath",
                imports: ["PropertyBased"]
            ),
            isComputedProperty: false
        )
        #expect(source.contains("let onceResult = value.lexicallyNormalized()"))
        #expect(source.contains("let twiceResult = onceResult.lexicallyNormalized()"))
    }
}
