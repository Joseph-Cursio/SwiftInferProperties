import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

// V1.52.D — unit tests for the v1.52 cycle (call-expression-shape
// classifier + stderr capture + GenericBindingResolver alignment).
// Four suites, one per workstream (D.1 classify / D.2 pair-resolver
// integration / D.3 stderr / D.4 GenericBindingResolver).

// MARK: - V1.52.D.1 — CallExpressionShape.classify

@Suite("V1.52.A — CallExpressionShape.classify")
struct V152CallExpressionShapeTests {

    @Test("operator-named function → .operatorFunction with paren form")
    func operatorClassifiesToOperatorFunction() {
        let result = CallExpressionShape.classify(
            typeQualifier: "Complex",
            bareFunctionName: "/"
        )
        #expect(result == .operatorFunction(name: "/"))
        #expect(result.rendered == "(/)")
    }

    @Test("EF-surface name on Complex carrier → .staticMethod (V1.54.A revert)")
    func elementaryFunctionOnComplexClassifiesToStaticMethod() {
        // V1.54.A — V1.52.A's free-function hypothesis reverted per
        // cycle-50 evidence. `Complex.exp(_:)` is the canonical Swift
        // syntax for the static method declared by ElementaryFunctions
        // and compiles cleanly from the workdir's imports.
        let result = CallExpressionShape.classify(
            typeQualifier: "Complex",
            bareFunctionName: "exp"
        )
        #expect(result == .staticMethod(qualifier: "Complex", method: "exp"))
        #expect(result.rendered == "Complex.exp")
    }

    @Test("static method on Int carrier → .staticMethod (default shape)")
    func staticMethodOnIntPreservedAsStaticMethod() {
        let result = CallExpressionShape.classify(
            typeQualifier: "Int",
            bareFunctionName: "binomial"
        )
        #expect(result == .staticMethod(qualifier: "Int", method: "binomial"))
        #expect(result.rendered == "Int.binomial")
    }

    @Test("non-EF carrier with EF-name → .staticMethod (no free-function lift)")
    func nonEFCarrierWithEFNameStaysStatic() {
        // `OrderedSet` is not in `freeFunctionMap`; even though `log`
        // is an EF surface name, the classifier must NOT lift it.
        let result = CallExpressionShape.classify(
            typeQualifier: "OrderedSet",
            bareFunctionName: "log"
        )
        #expect(result == .staticMethod(qualifier: "OrderedSet", method: "log"))
        #expect(result.rendered == "OrderedSet.log")
    }

    @Test("multi-character operator → .operatorFunction with full paren form")
    func multiCharacterOperatorClassifiesCorrectly() {
        let result = CallExpressionShape.classify(
            typeQualifier: "Complex",
            bareFunctionName: "<<"
        )
        #expect(result == .operatorFunction(name: "<<"))
        #expect(result.rendered == "(<<)")
    }

    @Test("Complex carrier with non-EF name (_relaxedMul) → .staticMethod")
    func complexCarrierWithNonEFNameStaysStatic() {
        // `_relaxedMul` isn't operator-named (underscore is not an
        // operator char) and isn't in the ElementaryFunctions surface,
        // so it must classify as a static method. Regression guard
        // for the V1.52.A risk #1 over-classification scenario.
        let result = CallExpressionShape.classify(
            typeQualifier: "Complex",
            bareFunctionName: "_relaxedMul"
        )
        #expect(result == .staticMethod(qualifier: "Complex", method: "_relaxedMul"))
        #expect(result.rendered == "Complex._relaxedMul")
    }

    @Test("Double + log → .staticMethod (V1.54.A revert)")
    func doubleWithLogClassifiesToStaticMethod() {
        // V1.54.A — reverted to .staticMethod per cycle-50 evidence.
        // `Double.log(_:)` is canonical Swift syntax for the static
        // method declared by ElementaryFunctions on Double.
        let result = CallExpressionShape.classify(
            typeQualifier: "Double",
            bareFunctionName: "log"
        )
        #expect(result == .staticMethod(qualifier: "Double", method: "log"))
        #expect(result.rendered == "Double.log")
    }

    @Test("isOperatorName edge cases (empty / mixed / digit)")
    func isOperatorNameEdgeCases() {
        // Empty: false (otherwise vacuous `allSatisfy` would return true).
        #expect(CallExpressionShape.isOperatorName("") == false)
        // Mixed alphanumeric + operator char: false.
        #expect(CallExpressionShape.isOperatorName("+1") == false)
        #expect(CallExpressionShape.isOperatorName("foo+") == false)
        // Pure operator chars: true.
        #expect(CallExpressionShape.isOperatorName("+") == true)
        #expect(CallExpressionShape.isOperatorName("==") == true)
        #expect(CallExpressionShape.isOperatorName("!=") == true)
        // Identifier with underscore: false (underscore is not an op char).
        #expect(CallExpressionShape.isOperatorName("_relaxedMul") == false)
    }
}
