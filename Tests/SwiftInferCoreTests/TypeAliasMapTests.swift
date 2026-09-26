@testable import SwiftInferCore
import Testing

/// The scan collects each non-generic `typealias`, bare and qualified, and drops a name two
/// declarations spell differently.
@Suite("Type aliases — collected for the generator resolver")
struct TypeAliasMapTests {

    @Test("a nested alias is recorded bare and qualified; a generic alias is not")
    func nestedAndGeneric() {
        let corpus = FunctionScanner.scanCorpus(source: """
            public struct BigUInt {
                public typealias Word = UInt
                public init(words: [Word]) {}
            }
            typealias Pair<T> = (T, T)
            """, file: "Big.swift")
        #expect(corpus.typeAliases["Word"] == "UInt")
        #expect(corpus.typeAliases["BigUInt.Word"] == "UInt")
        #expect(corpus.typeAliases["Pair"] == nil)
    }

    @Test("a bare name two declarations spell differently is dropped; qualified names survive")
    func conflictingBareName() {
        let first = FunctionScanner.scanCorpus(source: "struct A { typealias Word = UInt }", file: "A.swift")
        let second = FunctionScanner.scanCorpus(source: "struct B { typealias Word = UInt32 }", file: "B.swift")
        let merged = TypeAliasMap.merged([first.typeAliases, second.typeAliases])
        #expect(merged["Word"] == nil)
        #expect(merged["A.Word"] == "UInt")
        #expect(merged["B.Word"] == "UInt32")
    }
}
