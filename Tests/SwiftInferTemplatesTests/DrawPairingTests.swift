import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// #684 lever 2: one drawn argument sometimes taken from another (`DrawPairing`). The shapes are #665's
/// red relational rows: a name looked up in a drawn node, a set holding a drawn name, two equal strings.
@Suite("DrawPairing — relational draws that can line up")
struct DrawPairingTests {

    private static let node = "SwiftInferSyntaxCorpus.gen(FunctionCallExprSyntax.self)"

    /// `containsReference(to:in:)` draws the name BEFORE the node, so the pairing looks both ways.
    @Test("a String beside a syntax node takes a name from it, either side")
    func nameFrom() {
        #expect(DrawPairing.plan(argumentTypes: ["String", "FunctionCallExprSyntax"], generators: ["g", Self.node])
            == [0: .nameFrom(source: 1, target: .string)])
        let setPlan = DrawPairing.plan(
            argumentTypes: ["FunctionCallExprSyntax", "Set<String>"], generators: [Self.node, "g"]
        )
        #expect(setPlan == [1: .nameFrom(source: 0, target: .set)])
    }

    /// Review finding: `gen(ExprSyntax.self).optional` shares the prefix, and `name(near:)` on an
    /// optional does not compile.
    @Test("only a draw of the argument's own node type is a name source")
    func composedDrawIsNotANode() {
        let optional = "SwiftInferSyntaxCorpus.gen(ExprSyntax.self).optional"
        #expect(DrawPairing.plan(argumentTypes: ["ExprSyntax?", "String"], generators: [optional, "g"]).isEmpty)
        let array = "(SwiftInferSyntaxCorpus.gen(DeclSyntax.self)).array(of: 0...8)"
        let both = DrawPairing.plan(
            argumentTypes: ["[DeclSyntax]", "String", "FunctionCallExprSyntax"], generators: [array, "g", Self.node]
        )
        #expect(both == [1: .nameFrom(source: 2, target: .string)])
        let biased = "SwiftInferSyntaxCorpus.gen(FunctionCallExprSyntax.self, preferring: [\"x\"], kinds: [])"
        #expect(DrawPairing.plan(argumentTypes: ["FunctionCallExprSyntax", "String"], generators: [biased, "g"])
            == [1: .nameFrom(source: 0, target: .string)])
    }

    @Test("a String collection beside a String gets it; two equal types may copy")
    func memberAndCopy() {
        #expect(DrawPairing.plan(argumentTypes: ["String", "[String]"], generators: ["g", "h"])
            == [1: .memberOf(source: 0, target: .array)])
        #expect(DrawPairing.plan(argumentTypes: ["String", "String"], generators: ["g", "h"])
            == [1: .copyOf(source: 0)])
        #expect(DrawPairing.plan(argumentTypes: ["Int", "String"], generators: ["g", "h"]).isEmpty)
        #expect(DrawPairing.plan(argumentTypes: ["String"], generators: ["g"]).isEmpty)
    }

    @Test("pairings are applied after every draw, in argument order")
    func sampleShape() {
        let sample = LiftedTestEmitter.totalitySample(
            generators: ["G0", Self.node, "G2"],
            pairings: [0: .nameFrom(source: 1, target: .string), 2: .copyOf(source: 0)]
        )
        let lines = sample.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines == [
            "{ rng in",
            "var arg0 = (G0).run(using: &rng)",
            "let arg1 = (\(Self.node)).run(using: &rng)",
            "var arg2 = (G2).run(using: &rng)",
            "if Bool.random(using: &rng), let name = SwiftInferSyntaxCorpus.name(near: arg1, using: &rng) "
                + "{ arg0 = name }",
            "if Int.random(in: 0 ..< 4, using: &rng) == 0 { arg2 = arg0 }",
            "return (arg0, arg1, arg2)",
            "}",
        ])
    }

    @Test("no pairings emit exactly the sample they always did")
    func unpairedUnchanged() {
        #expect(LiftedTestEmitter.totalitySample(generators: ["A", "B"])
            == LiftedTestEmitter.totalitySample(generators: ["A", "B"], pairings: [:]))
        #expect(LiftedTestEmitter.totalitySample(generators: ["A", "B"]).contains("let arg1 = (B).run(using: &rng)"))
    }

    @Test("collection targets append or insert")
    func collectionStatements() {
        #expect(DrawPairing.memberOf(source: 0, target: .set).statement(for: 1)
            == "if Bool.random(using: &rng) { arg1.insert(arg0) }")
        let statement = DrawPairing.nameFrom(source: 0, target: .array).statement(for: 1)
        #expect(statement.hasSuffix("{ arg1.append(name) }"))
    }
}
