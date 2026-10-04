import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("LiftedTestEmitter — reference-oracle scaffold (B25 / issue #1)")
struct PredicateReferenceOracleEmitterTests {

    private static let seed = SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4)

    private static func argument(
        label: String? = nil,
        name: String,
        type: String,
        generator: String
    ) -> LiftedTestEmitter.ReferenceOracleArgument {
        .init(
            parameter: Parameter(label: label, internalName: name, typeText: type, isInout: false),
            generator: generator
        )
    }

    @Test("single param: emits a reference stub carrying the docstring, plus the code-vs-oracle property")
    func singleParameter() {
        let source = LiftedTestEmitter.referenceOracle(
            funcName: "isValidQuantity",
            arguments: [Self.argument(name: "quantity", type: "Double", generator: "Gen<Double>.double()")],
            returnTypeText: "Bool",
            docComment: "A quantity is valid when it is finite and not negative. Zero is allowed.",
            seed: Self.seed
        )
        #expect(source.contains("func isValidQuantity_reference(_ quantity: Double) -> Bool"))
        #expect(source.contains("fatalError(\"state the reference definition"))
        #expect(source.contains("A quantity is valid when it is finite and not negative. Zero is allowed."))
        #expect(source.contains("isValidQuantity(value) == isValidQuantity_reference(value)"))
        #expect(source.contains("@Test func isValidQuantity_matchesReferenceDefinition()"))
        // Edge-biased generator: uniform baseline mixed with the boundary values.
        #expect(source.contains("Gen.frequency"))
        #expect(source.contains("[0.0, -1.0, 1.0] as [Double]"))
        // Bool return needs no Equatable note.
        #expect(!source.contains("must be Equatable"))
    }

    @Test("single param: a labelled parameter is reconstructed and called with its label")
    func labelledParameter() {
        let source = LiftedTestEmitter.referenceOracle(
            funcName: "accepts",
            arguments: [Self.argument(label: "code", name: "value", type: "String", generator: "Gen<String>.string()")],
            returnTypeText: "Bool",
            docComment: "Accepts a code when it is exactly six uppercase letters.",
            seed: Self.seed
        )
        #expect(source.contains("func accepts_reference(code value: String) -> Bool"))
        #expect(source.contains("accepts(code: value) == accepts_reference(code: value)"))
    }

    @Test("single param: an Int predicate edge-biases toward 0 and ±1")
    func integerEdgeBias() {
        let source = LiftedTestEmitter.referenceOracle(
            funcName: "isValidServings",
            arguments: [Self.argument(name: "servings", type: "Int", generator: "Gen<Int>.int()")],
            returnTypeText: "Bool",
            docComment: "A serving count is valid when it is strictly greater than zero.",
            seed: Self.seed
        )
        #expect(source.contains("[0, -1, 1] as [Int]"))
        // Bounded baseline, not the unbounded Gen<Int>.int() — an unbounded draw
        // hangs any function that loops O(n) on the parameter.
        #expect(source.contains("Gen<Int>.boundedForArithmetic()"))
        #expect(!source.contains("Gen<Int>.int()"))
    }

    @Test("multi param: draws a tuple, indexes it, and preserves labels in both calls")
    func multiParameter() {
        let source = LiftedTestEmitter.referenceOracle(
            funcName: "canReach",
            arguments: [
                Self.argument(label: "from", name: "origin", type: "Int", generator: "Gen<Int>.int()"),
                Self.argument(label: "to", name: "target", type: "Int", generator: "Gen<Int>.int()")
            ],
            returnTypeText: "Bool",
            docComment: "Reachable when the target is within range of the origin.",
            seed: Self.seed
        )
        #expect(source.contains("func canReach_reference(from origin: Int, to target: Int) -> Bool"))
        #expect(source.contains("{ tuple in"))
        #expect(source.contains(
            "canReach(from: tuple.0, to: tuple.1) == canReach_reference(from: tuple.0, to: tuple.1)"
        ))
        #expect(source.contains("[0, -1, 1] as [Int]"))
    }

    @Test("fallback contract: a non-Bool return emits a value-typed reference and an Equatable note")
    func nonBoolReturn() {
        let source = LiftedTestEmitter.referenceOracle(
            funcName: "roundToPlaces",
            arguments: [
                Self.argument(name: "value", type: "Double", generator: "Gen<Double>.double()"),
                Self.argument(label: "places", name: "places", type: "Int", generator: "Gen<Int>.int()")
            ],
            returnTypeText: "Double",
            docComment: "Rounds to the nearest multiple; negative places treated as zero.",
            seed: Self.seed
        )
        #expect(source.contains("func roundToPlaces_reference(_ value: Double, places: Int) -> Double"))
        #expect(source.contains("(the return type Double must be Equatable for this to compile)"))
        #expect(source.contains(
            "roundToPlaces(tuple.0, places: tuple.1) == roundToPlaces_reference(tuple.0, places: tuple.1)"
        ))
        // The Int `places` is edge-biased to include the negative boundary the bug hides at.
        #expect(source.contains("[0, -1, 1] as [Int]"))
    }

    /// A tuple is never `Equatable`, so "the return type must be Equatable" asks for a
    /// conformance that cannot exist — while `f(x) == f_reference(x)` over a tuple of `Equatable`
    /// elements compiles, through the standard library's tuple `==`.
    @Test("fallback contract: a tuple return gets the element-wise note, not the conformance one")
    func tupleReturn() {
        let source = LiftedTestEmitter.referenceOracle(
            funcName: "clip",
            arguments: [
                Self.argument(name: "text", type: "String", generator: "Gen<String>.string()"),
                Self.argument(name: "budget", type: "Int", generator: "Gen<Int>.int()")
            ],
            returnTypeText: "(text: String, didTruncate: Bool)",
            docComment: "The result never exceeds the byte budget.",
            seed: Self.seed
        )
        #expect(source.contains(
            "func clip_reference(_ text: String, _ budget: Int) -> (text: String, didTruncate: Bool)"
        ))
        #expect(source.contains("must be Equatable for this to compile)") == false)
        #expect(source.contains("every element of the returned tuple must be Equatable"))
        #expect(source.contains("clip(tuple.0, tuple.1) == clip_reference(tuple.0, tuple.1)"))
    }

    /// The note above a reference stub whose `R` is `returnTypeText`, for a one-`Int` subject.
    private static func note(forReturnType returnTypeText: String) -> String {
        let source = LiftedTestEmitter.referenceOracle(
            funcName: "pairs",
            arguments: [Self.argument(name: "count", type: "Int", generator: "Gen<Int>.int()")],
            returnTypeText: returnTypeText,
            docComment: "Pairs each index with its square.",
            seed: Self.seed
        )
        return source.split(separator: "\n").first { $0.hasPrefix("// (") }.map(String.init) ?? ""
    }

    /// **A tuple shape Swift has no `==` for gets no conformance advice**: no element being
    /// `Equatable` would make `f(x) == f_reference(x)` compile, so the note says it cannot.
    /// Checked with `swiftc` on Swift 6.4 for each spelling, as the result of both functions.
    @Test("fallback contract: a tuple shape with no `==` says the comparison cannot compile", arguments: [
        ("(Int, (Int, Int))", "itself a tuple"),
        ("Swift.Optional<(Int, Int)>", "inside an Optional or a collection"),
        ("(Int, Int, Int, Int, Int, Int, Int)", "at most six")
    ])
    func tupleShapeWithNoEquality(returnTypeText: String, obstacle: String) {
        let note = Self.note(forReturnType: returnTypeText)
        #expect(note.hasPrefix("// (this cannot compile as written: the function returns "))
        #expect(note.contains(obstacle))
        #expect(note.contains("must be Equatable") == false)
    }

    /// `(Int, Int)!` is force-unwrapped once `Optional`'s `==` fails to type-check, and
    /// `sending` is not part of the type — so `pairs(value) == pairs_reference(value)` compiles
    /// over both through tuple `==` (`swiftc`, Swift 6.4), and the element-wise note is the one
    /// that is true.
    @Test("fallback contract: an implicitly unwrapped or `sending` tuple gets the element-wise note", arguments: [
        "(Int, Int)!",
        "sending (Int, Int)"
    ])
    func tupleSpelledAnotherWay(returnTypeText: String) {
        #expect(Self.note(forReturnType: returnTypeText).hasPrefix(
            "// (every element of the returned tuple must be Equatable for this to compile"
        ))
    }
}
