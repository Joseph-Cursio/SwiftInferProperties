import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// An operator subject is written in operator form and named in words — BigInt's
/// `static func +(a: BigInt, b: BigInt)` had every arithmetic stub set aside on
/// `@Test func +_isCommutative()` calling `+(a: pair.0, b: pair.1)`, neither of which parses.
@Suite("Operator subjects in emitted stubs")
struct OperatorStubSpellingTests {

    private static let plus = CalleeReference(bareName: "+", argumentLabels: ["a", "b"])
    private static let tilde = CalleeReference(bareName: "~", argumentLabels: ["x"])

    @Test("a binary operator is called infix, labels dropped")
    func binaryInfix() {
        #expect(Self.plus.call("pair.0", "pair.1") == "(pair.0 + pair.1)")
    }

    @Test("a unary operator is called prefix, and nests")
    func unaryPrefix() {
        #expect(Self.tilde.call(Self.tilde.call("value")) == "~(~(value))")
    }

    @Test("the test name spells the operator out; an ordinary name is untouched")
    func identifierNames() {
        #expect(Self.plus.identifierName == "plus")
        #expect(CalleeReference(bareName: "&+").identifierName == "ampersandPlus")
        #expect(CalleeReference(bareName: "merge").identifierName == "merge")
    }

    @Test("the commutativity stub names and calls the operator validly")
    func commutativityStub() {
        let stub = LiftedTestEmitter.commutative(
            callee: Self.plus, typeName: "BigInt", seed: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            generator: "BigInt.gen()"
        )
        #expect(stub.contains("func plus_isCommutative()"))
        #expect(stub.contains("{ (pair: (BigInt, BigInt)) in (pair.0 + pair.1) == (pair.1 + pair.0) }"))
        #expect(!stub.contains("+(a:"))
    }

    @Test("a named function's closure stays untyped")
    func namedFunctionUntouched() {
        let stub = LiftedTestEmitter.commutative(
            callee: "merge", typeName: "Doc", seed: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            generator: "Doc.gen()"
        )
        #expect(stub.contains("{ pair in merge(pair.0, pair.1) == merge(pair.1, pair.0) }"))
    }
}
