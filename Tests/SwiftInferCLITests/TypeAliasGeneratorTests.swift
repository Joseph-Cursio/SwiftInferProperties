import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A type whose initializers take an alias derives once the resolver is told the alias exists —
/// BigInt's `init(words: [Word])`, with `typealias Word = UInt`.
@Suite("Type aliases reach the accept path's generator")
struct TypeAliasGeneratorTests {

    private static let corpus = FunctionScanner.scanCorpus(source: """
        public struct BigUInt: Equatable {
            public typealias Word = UInt
            var storage: [Word]
            public init(words: [Word]) { storage = words }
        }
        """, file: "Big.swift")

    private static var shapes: [TypeShape] { TypeShapeBuilder.shapes(from: corpus.typeDecls) }

    @Test("with the aliases, BigUInt derives through init(words:)")
    func aliasResolves() throws {
        let generate = InteractiveTriage.projectTypeGenerator(types: Self.shapes, aliases: Self.corpus.typeAliases)
        let expression = try #require(generate("BigUInt"))
        #expect(expression.contains("BigUInt(words:"), "got: \(expression)")
    }

    @Test("without them, it reports no generator, naming the alias")
    func withoutAliasesNoGenerator() throws {
        let expression = try #require(InteractiveTriage.projectTypeGenerator(types: Self.shapes)("BigUInt"))
        #expect(expression.contains("no generator derived"))
        #expect(expression.contains("`Word` does not"))
    }
}
