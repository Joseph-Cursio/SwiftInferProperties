import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("LiftedTestEmitter — predicate reference-oracle scaffold (B25 / issue #1)")
struct PredicateReferenceOracleEmitterTests {

    private static let seed = SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4)

    @Test("single param: emits a reference stub carrying the docstring, plus the predicate-vs-oracle property")
    func singleParameter() {
        let source = LiftedTestEmitter.predicateReferenceOracle(
            funcName: "isValidQuantity",
            parameters: [Parameter(label: nil, internalName: "quantity", typeText: "Double", isInout: false)],
            docComment: "A quantity is valid when it is finite and not negative. Zero is allowed.",
            seed: Self.seed,
            generators: ["Gen<Double>.double()"]
        )
        #expect(source.contains("func isValidQuantity_reference(_ quantity: Double) -> Bool"))
        #expect(source.contains("fatalError(\"state the reference definition"))
        #expect(source.contains("A quantity is valid when it is finite and not negative. Zero is allowed."))
        #expect(source.contains("isValidQuantity(value) == isValidQuantity_reference(value)"))
        #expect(source.contains("@Test func isValidQuantity_matchesReferenceDefinition()"))
        // Edge-biased generator: the uniform baseline mixed with the boundary
        // values (above all 0.0) where `> 0` vs `>= 0` contract bugs hide.
        #expect(source.contains("Gen.frequency"))
        #expect(source.contains("[0.0, -1.0, 1.0] as [Double]"))
    }

    @Test("single param: a labelled parameter is reconstructed and called with its label")
    func labelledParameter() {
        let source = LiftedTestEmitter.predicateReferenceOracle(
            funcName: "accepts",
            parameters: [Parameter(label: "code", internalName: "value", typeText: "String", isInout: false)],
            docComment: "Accepts a code when it is exactly six uppercase letters.",
            seed: Self.seed,
            generators: ["Gen<String>.string()"]
        )
        #expect(source.contains("func accepts_reference(code value: String) -> Bool"))
        #expect(source.contains("accepts(code: value) == accepts_reference(code: value)"))
    }

    @Test("single param: an Int predicate edge-biases toward 0 and ±1")
    func integerEdgeBias() {
        let source = LiftedTestEmitter.predicateReferenceOracle(
            funcName: "isValidServings",
            parameters: [Parameter(label: nil, internalName: "servings", typeText: "Int", isInout: false)],
            docComment: "A serving count is valid when it is strictly greater than zero.",
            seed: Self.seed,
            generators: ["Gen<Int>.int()"]
        )
        #expect(source.contains("[0, -1, 1] as [Int]"))
    }

    @Test("multi param: draws a tuple, indexes it, and preserves labels in both calls")
    func multiParameter() {
        let source = LiftedTestEmitter.predicateReferenceOracle(
            funcName: "canReach",
            parameters: [
                Parameter(label: "from", internalName: "origin", typeText: "Int", isInout: false),
                Parameter(label: "to", internalName: "target", typeText: "Int", isInout: false)
            ],
            docComment: "Reachable when the target is within range of the origin.",
            seed: Self.seed,
            generators: ["Gen<Int>.int()", "Gen<Int>.int()"]
        )
        // Reference stub carries the full labelled signature.
        #expect(source.contains("func canReach_reference(from origin: Int, to target: Int) -> Bool"))
        // Tuple sample + tuple-indexed, label-preserving calls.
        #expect(source.contains("{ tuple in"))
        #expect(source.contains(
            "canReach(from: tuple.0, to: tuple.1) == canReach_reference(from: tuple.0, to: tuple.1)"
        ))
        // Each parameter is edge-biased.
        #expect(source.contains("[0, -1, 1] as [Int]"))
    }
}
