import Foundation
import Testing
@testable import SwiftInferCore

@Suite("FunctionScanner.scanCorpus — type-decl emission (M3.2)")
struct TypeDeclScannerTests {

    // MARK: Primary type kinds

    @Test
    func capturesStructWithName() throws {
        let source = """
        struct IntSet {
            let count: Int
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.name == "IntSet")
        #expect(decl.kind == .struct)
        #expect(decl.inheritedTypes.isEmpty)
    }

    @Test
    func capturesEachPrimaryKind() {
        let source = """
        struct S {}
        class C {}
        enum E {}
        actor A {}
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let pairs = corpus.typeDecls.map { ($0.name, $0.kind) }
        #expect(pairs.count == 4)
        #expect(pairs[0].0 == "S" && pairs[0].1 == .struct)
        #expect(pairs[1].0 == "C" && pairs[1].1 == .class)
        #expect(pairs[2].0 == "E" && pairs[2].1 == .enum)
        #expect(pairs[3].0 == "A" && pairs[3].1 == .actor)
    }

    // MARK: Inheritance clause — full text per source

    @Test
    func capturesInheritedConformancesInSourceOrder() throws {
        let source = """
        struct Token: Hashable, Equatable, CustomStringConvertible {
            let raw: String
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.inheritedTypes == ["Hashable", "Equatable", "CustomStringConvertible"])
    }

    @Test
    func capturesGenericConformanceTextVerbatim() throws {
        let source = """
        struct Bag<Element>: Collection where Element: Hashable {
            var underestimatedCount: Int { 0 }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.name == "Bag")
        #expect(decl.inheritedTypes == ["Collection"])
    }

    // MARK: Extension emission — open decision #2

    @Test
    func extensionEmitsTypeDeclForExtendedType() throws {
        // Open decision #2 default (a): extensions emit a TypeDecl whose
        // inheritedTypes carry just the conformances the extension adds.
        // Resolver merges multiple TypeDecls per name in M3.3.
        let source = """
        extension Foo: Equatable {}
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.name == "Foo")
        #expect(decl.kind == .extension)
        #expect(decl.inheritedTypes == ["Equatable"])
    }

    @Test
    func extensionWithoutInheritanceEmitsEmptyInheritedTypes() throws {
        let source = """
        extension Foo {
            func bar() -> Int { 0 }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.name == "Foo")
        #expect(decl.kind == .extension)
        #expect(decl.inheritedTypes.isEmpty)
    }

    @Test
    func primaryDeclAndExtensionForSameTypeEmitSeparateRecords() {
        // Mergeable multimap shape — two records share a name.
        let source = """
        struct Foo {
            let n: Int
        }
        extension Foo: Equatable {}
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let kindsByName = corpus.typeDecls.reduce(into: [String: [TypeDecl.Kind]]()) {
            $0[$1.name, default: []].append($1.kind)
        }
        #expect(kindsByName["Foo"] == [.struct, .extension])
    }

    // MARK: Nested types

    @Test
    func nestedTypesEachEmitTheirOwnTypeDecl() {
        let source = """
        struct Outer {
            struct Inner {
                let x: Int
            }
            enum Tag { case a, b }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let names = corpus.typeDecls.map(\.name)
        #expect(names == ["Outer", "Inner", "Tag"])
    }

    // MARK: Protocol decls — skipped

    @Test
    func protocolDeclsAreNotEmittedAsTypeDecls() {
        // Protocol bodies are intentionally skipped by the scanner — they
        // contribute no `Equatable` evidence about concrete types and the
        // existing visitor short-circuits with `.skipChildren`.
        let source = """
        protocol Named {
            var name: String { get }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        #expect(corpus.typeDecls.isEmpty)
    }

    // MARK: Location

    @Test
    func locationPointsAtIntroducerKeyword() throws {
        let source = """
        // header comment
        struct Widget {
            let id: Int
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.location.file == "Test.swift")
        #expect(decl.location.line == 2)
    }

    // MARK: Single-pass coexistence with summaries + identities

    @Test
    func singlePassEmitsSummariesIdentitiesAndTypeDecls() {
        let source = """
        struct IntSet: Equatable {
            static let empty: IntSet = IntSet()
            func merge(_ a: IntSet, _ b: IntSet) -> IntSet { return a }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        #expect(corpus.summaries.map(\.name) == ["merge"])
        #expect(corpus.identities.map(\.name) == ["empty"])
        #expect(corpus.typeDecls.map(\.name) == ["IntSet"])
        #expect(corpus.typeDecls.first?.inheritedTypes == ["Equatable"])
    }

    // MARK: scanCorpus — directory pass

    @Test
    func directoryScanCorpusAccumulatesTypeDeclsAcrossFiles() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypeDeclScanTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try """
        struct A: Equatable {}
        """.write(
            to: temp.appendingPathComponent("A.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        struct B {}
        extension B: Hashable {}
        """.write(
            to: temp.appendingPathComponent("B.swift"),
            atomically: true,
            encoding: .utf8
        )

        let corpus = try FunctionScanner.scanCorpus(directory: temp)
        let names = corpus.typeDecls.map(\.name)
        #expect(names == ["A", "B", "B"])
        let kinds = corpus.typeDecls.map(\.kind)
        #expect(kinds == [.struct, .struct, .extension])
    }
}
