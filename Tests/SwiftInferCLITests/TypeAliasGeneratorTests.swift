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

    /// BigInt's own shape: four `Word`s, so the bare name is ambiguous and dropped from the map, yet
    /// inside `BigUInt` it can only mean `BigUInt.Word`, and `BigInt.Word` reaches `UInt` through it.
    private static let ambiguous = FunctionScanner.scanCorpus(source: """
        public struct BigUInt: Equatable {
            public typealias Word = UInt
            var storage: [Word]
            public init(words: [Word]) { storage = words }
        }
        public struct BigInt: Equatable {
            public typealias Word = BigUInt.Word
            var magnitude: [Word]
            public init(word: Word) { magnitude = [word] }
        }
        public struct Units<Words: Collection> {
            public typealias Word = Words.Element
        }
        """, file: "Big.swift")

    @Test("an ambiguous bare alias still resolves inside the type that declares it")
    func scopedAliasResolves() throws {
        #expect(Self.ambiguous.typeAliases["Word"] == nil)
        let shapes = TypeShapeBuilder.shapes(from: Self.ambiguous.typeDecls)
        let generate = InteractiveTriage.projectTypeGenerator(types: shapes, aliases: Self.ambiguous.typeAliases)
        let unsigned = try #require(generate("BigUInt"))
        #expect(unsigned.contains("BigUInt(words:"), "got: \(unsigned)")
        let signed = try #require(generate("BigInt"))
        #expect(signed.contains("BigInt(word:"), "got: \(signed)")
    }

    @Test("the rewrite touches only a bare name, following the alias chain")
    func rewriteIsScoped() {
        let aliases = ["BigUInt.Word": "UInt", "BigInt.Word": "BigUInt.Word"]
        let rewrite = { TypeAliasMap.resolvingNestedAliases(in: $0, declaredOn: $1, aliases: aliases) }
        #expect(rewrite("[Word]", "BigInt") == "[UInt]")
        #expect(rewrite("Foo.Word", "BigInt") == "Foo.Word")
        #expect(rewrite("Words", "BigInt") == "Words")
        #expect(rewrite("Word", "Other") == "Word")
    }
}
