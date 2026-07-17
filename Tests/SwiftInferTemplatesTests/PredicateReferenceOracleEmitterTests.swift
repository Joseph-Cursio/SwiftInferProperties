import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("LiftedTestEmitter — predicate reference-oracle scaffold (B25 / issue #1)")
struct PredicateReferenceOracleEmitterTests {

    private static let seed = SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4)

    @Test("emits a reference stub carrying the docstring, plus the predicate-vs-oracle property")
    func emitsStubAndProperty() {
        let source = LiftedTestEmitter.predicateReferenceOracle(
            funcName: "isValidQuantity",
            parameter: Parameter(label: nil, internalName: "quantity", typeText: "Double", isInout: false),
            docComment: "A quantity is valid when it is finite and not negative. Zero is allowed.",
            seed: Self.seed,
            generator: "Gen<Double>.double()"
        )
        // The reference-oracle stub the reader fills.
        #expect(source.contains("func isValidQuantity_reference(_ quantity: Double) -> Bool"))
        #expect(source.contains("fatalError(\"state the reference definition"))
        // The docstring is surfaced verbatim as the definition being encoded.
        #expect(source.contains("A quantity is valid when it is finite and not negative. Zero is allowed."))
        // The property runs the predicate against the reader's oracle.
        #expect(source.contains("isValidQuantity(value) == isValidQuantity_reference(value)"))
        #expect(source.contains("@Test func isValidQuantity_matchesReferenceDefinition()"))
        // It draws inputs from an EDGE-BIASED generator — the uniform baseline
        // mixed with the boundary values (above all 0.0) where predicate contract
        // bugs like `> 0` vs `>= 0` hide. A uniform draw would false-pass.
        #expect(source.contains("Gen.frequency"))
        #expect(source.contains("Gen<Double>.double()"))
        #expect(source.contains("[0.0, -1.0, 1.0] as [Double]"))
    }

    @Test("an Int predicate edge-biases toward 0 and ±1")
    func integerEdgeBias() {
        let source = LiftedTestEmitter.predicateReferenceOracle(
            funcName: "isValidServings",
            parameter: Parameter(label: nil, internalName: "servings", typeText: "Int", isInout: false),
            docComment: "A serving count is valid when it is strictly greater than zero.",
            seed: Self.seed,
            generator: "Gen<Int>.int()"
        )
        #expect(source.contains("[0, -1, 1] as [Int]"))
    }

    @Test("a labelled parameter is reconstructed with its label")
    func labelledParameterClause() {
        let source = LiftedTestEmitter.predicateReferenceOracle(
            funcName: "accepts",
            parameter: Parameter(label: "code", internalName: "value", typeText: "String", isInout: false),
            docComment: "Accepts a code when it is exactly six uppercase letters.",
            seed: Self.seed,
            generator: "Gen<String>.string()"
        )
        #expect(source.contains("func accepts_reference(code value: String) -> Bool"))
        #expect(source.contains("accepts(value) == accepts_reference(value)"))
    }
}
