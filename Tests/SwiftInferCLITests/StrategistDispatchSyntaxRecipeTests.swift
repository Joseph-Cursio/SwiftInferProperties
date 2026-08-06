import Foundation
@testable import SwiftInferCLI
import Testing

/// SwiftSyntax node carriers resolve a generator instead of declining.
///
/// Measured on SwiftProjectLint (60 picks across six packages): 34 declined as
/// `unsupported-carrier`, and **30 of those 34 were SwiftSyntax node types**.
/// Half the corpus was unverifiable because nothing could produce a compiler AST
/// node.
///
/// These tests pin the *shape* of what the recipes emit rather than the emitted
/// string verbatim. A snapshot of the whole expression would fail on every
/// corpus edit — and the corpora are meant to grow, since the strength of a
/// totality pass is bounded by how many structurally distinct trees it saw.
@Suite("Strategist dispatch — SwiftSyntax carrier recipes")
struct StrategistDispatchSyntaxRecipeTests {

    /// The carriers the SwiftProjectLint survey actually declined on, plus the
    /// two root types every walker takes. If one of these regresses to
    /// `unsupported-carrier`, a measured block of that corpus goes dark again.
    static let measuredCarriers = [
        "Syntax",
        "SourceFileSyntax",
        "FunctionCallExprSyntax",
        "StructDeclSyntax",
        "ClassDeclSyntax",
        "ClosureExprSyntax",
        "AccessorBlockSyntax",
        "AttributeListSyntax",
        "MemberBlockSyntax",
        "PatternBindingSyntax",
        "CodeBlockSyntax",
        "FunctionDeclSyntax"
    ]

    @Test("every measured syntax carrier resolves a recipe", arguments: measuredCarriers)
    func measuredCarrierResolves(carrier: String) throws {
        let recipe = try StrategistDispatchEmitter.resolveRecipe(carrier: carrier, typeShape: nil)
        #expect(recipe.carrierTypeName == carrier)
        #expect(!recipe.expression.isEmpty)
    }

    /// The recipes parse source rather than construct nodes, so the stub needs
    /// both modules. A missing import here surfaces as `build-failed` on every
    /// entry using the carrier — the same costume a real coverage limit wears,
    /// which is why it is asserted rather than assumed.
    @Test("a syntax recipe imports SwiftParser and SwiftSyntax")
    func syntaxRecipeDeclaresItsImports() throws {
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "FunctionCallExprSyntax", typeShape: nil
        )
        #expect(recipe.imports.contains("SwiftParser"))
        #expect(recipe.imports.contains("SwiftSyntax"))
        #expect(recipe.imports.contains("PropertyBased"))
    }

    /// Parsed, not constructed. A hand-built node has whatever shape the builder
    /// gave it; a parsed one carries the trivia, token layout, and parent chain a
    /// visitor meets in the field — and since the `predicate` law is totality,
    /// the realism of the input is the entire experiment.
    @Test("a syntax recipe parses real source")
    func syntaxRecipeParsesSource() throws {
        let recipe = try StrategistDispatchEmitter.resolveRecipe(carrier: "Syntax", typeShape: nil)
        #expect(recipe.expression.contains("Parser.parse(source:"))
    }

    /// The outer `Gen` must be the only source of randomness, or the Xoshiro
    /// seed → outcome chain the verify harness replays on breaks. The corpus is
    /// indexed by the generated seed; nothing else varies.
    @Test("a syntax recipe draws from a seeded generator")
    func syntaxRecipeIsSeeded() throws {
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "StructDeclSyntax", typeShape: nil
        )
        #expect(recipe.expression.contains("Gen<Int>.int(in:"))
        #expect(recipe.expression.contains("corpus.count"))
    }

    /// A totality law over one tree sampled a hundred times proves nothing. Each
    /// carrier must offer several structurally distinct snippets — this asserts
    /// the corpus is plural, which is the floor for the claim being meaningful.
    @Test("each measured carrier draws from more than one shape", arguments: measuredCarriers)
    func corpusHasSeveralShapes(carrier: String) throws {
        let recipe = try StrategistDispatchEmitter.resolveRecipe(carrier: carrier, typeShape: nil)
        // Corpus entries are string literals in a `[String]` array literal;
        // two or more means at least one separator between them.
        let separators = recipe.expression.components(separatedBy: "\", \"").count - 1
        #expect(separators >= 1, "corpus for \(carrier) has fewer than two shapes")
    }

    // MARK: - Not over-capturing

    /// The table must not swallow carriers it has no recipe for. An unknown
    /// external type still declines, and declining honestly is the behaviour the
    /// Unverifiable bucket depends on.
    @Test("an unrelated external carrier still declines")
    func unrelatedCarrierStillDeclines() {
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.resolveRecipe(
                carrier: "SomeUnknownExternalType", typeShape: nil
            )
        }
    }

    /// An opaque type cannot be bound to a concrete node kind, so there is
    /// nothing to generate. Named here because it is a *permanent* member of the
    /// Unverifiable bucket rather than a gap someone should try to close.
    @Test("an opaque `some SyntaxProtocol` carrier declines")
    func opaqueCarrierDeclines() {
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.resolveRecipe(
                carrier: "some SyntaxProtocol", typeShape: nil
            )
        }
    }

    /// Stdlib carriers take the `RawType` branch, which is checked before this
    /// table. Asserted so a future entry keyed on a common name cannot quietly
    /// shadow them.
    @Test("stdlib carriers keep their existing generator")
    func stdlibCarriersUnaffected() throws {
        let recipe = try StrategistDispatchEmitter.resolveRecipe(carrier: "String", typeShape: nil)
        #expect(recipe.carrierTypeName == "String")
        #expect(!recipe.expression.contains("Parser.parse"))
    }
}
