import Foundation
import Testing

@testable import SwiftInferCLI

// V1.149 — a function with external argument labels can't be called
// positionally (`ref(value)`); the stub wraps it in a label-carrying
// trampoline closure. Label-free functions are returned unchanged so
// existing stdlib-carrier stubs stay byte-identical.
@Suite("VerifyCommand — V1.149 labeled call expression")
struct LabeledCallExpressionTests {

    private typealias V = SwiftInferCommand.Verify

    @Test("argument labels parse from the display name")
    func labelsParse() {
        #expect(V.argumentLabels(from: "indent(in:)") == ["in"])
        #expect(V.argumentLabels(from: "pick(a:b:)") == ["a", "b"])
        #expect(V.argumentLabels(from: "clamp(_:)") == ["_"])
        #expect(V.argumentLabels(from: "now()") == [])
    }

    @Test("a labeled single-arg function is wrapped in a trampoline closure")
    func labeledSingleArgWraps() {
        let call = V.labeledCallExpression(
            primaryFunctionName: "indentBlockSequences(in:)",
            reference: "YAMLConfigurationEngine.indentBlockSequences"
        )
        #expect(call == "{ YAMLConfigurationEngine.indentBlockSequences(in: $0) }")
    }

    @Test("a labeled two-arg function threads both labels positionally")
    func labeledTwoArgWraps() {
        let call = V.labeledCallExpression(
            primaryFunctionName: "combine(lhs:rhs:)",
            reference: "Engine.combine"
        )
        #expect(call == "{ Engine.combine(lhs: $0, rhs: $1) }")
    }

    @Test("a label-free function is returned unchanged (no golden churn)")
    func unlabeledUnchanged() {
        let underscore = V.labeledCallExpression(
            primaryFunctionName: "normalize(_:)",
            reference: "Foo.normalize"
        )
        #expect(underscore == "Foo.normalize")
        let noArgs = V.labeledCallExpression(
            primaryFunctionName: "identity()",
            reference: "Foo.identity"
        )
        #expect(noArgs == "Foo.identity")
    }
}
