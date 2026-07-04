import Foundation
import Testing

@testable import SwiftInferCLI

// V1.149 — a function with external argument labels can't be called
// positionally (`ref(value)`); the stub wraps it in a label-carrying
// trampoline closure. Label-free functions are returned unchanged so
// existing stdlib-carrier stubs stay byte-identical.
@Suite("VerifyCommand — V1.149 labeled call expression")
struct LabeledCallExpressionTests {

    private typealias VerifyCLI = SwiftInferCommand.Verify

    @Test("argument labels parse from the display name")
    func labelsParse() {
        #expect(VerifyCLI.argumentLabels(from: "indent(in:)") == ["in"])
        #expect(VerifyCLI.argumentLabels(from: "pick(a:b:)") == ["a", "b"])
        #expect(VerifyCLI.argumentLabels(from: "clamp(_:)") == ["_"])
        #expect(VerifyCLI.argumentLabels(from: "now()").isEmpty)
    }

    @Test("a labeled single-arg function is wrapped in a trampoline closure")
    func labeledSingleArgWraps() {
        let call = VerifyCLI.labeledCallExpression(
            primaryFunctionName: "indentBlockSequences(in:)",
            reference: "YAMLConfigurationEngine.indentBlockSequences"
        )
        #expect(call == "{ YAMLConfigurationEngine.indentBlockSequences(in: $0) }")
    }

    @Test("a labeled two-arg function threads both labels positionally")
    func labeledTwoArgWraps() {
        let call = VerifyCLI.labeledCallExpression(
            primaryFunctionName: "combine(lhs:rhs:)",
            reference: "Engine.combine"
        )
        #expect(call == "{ Engine.combine(lhs: $0, rhs: $1) }")
    }

    @Test("a label-free function is returned unchanged (no golden churn)")
    func unlabeledUnchanged() {
        let underscore = VerifyCLI.labeledCallExpression(
            primaryFunctionName: "normalize(_:)",
            reference: "Foo.normalize"
        )
        #expect(underscore == "Foo.normalize")
        let noArgs = VerifyCLI.labeledCallExpression(
            primaryFunctionName: "identity()",
            reference: "Foo.identity"
        )
        #expect(noArgs == "Foo.identity")
    }
}
