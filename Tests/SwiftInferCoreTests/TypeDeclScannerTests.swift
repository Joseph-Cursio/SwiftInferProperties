import Foundation
import ProtoLawCore
import Testing
@testable import SwiftInferCore

@Suite("FunctionScanner.scanCorpus — type-decl emission (M3.2)")
struct TypeDeclScannerBasicsTests {

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

@Suite("FunctionScanner.scanCorpus — stored members + init/gen detection (M4.1)")
struct TypeDeclScannerStoredMembersTests {

    @Test
    func capturesStoredMembersInSourceOrder() throws {
        let source = """
        struct Point {
            let x: Int
            let y: Int
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.storedMembers.map(\.name) == ["x", "y"])
        #expect(decl.storedMembers.map(\.typeName) == ["Int", "Int"])
        #expect(decl.hasUserInit == false)
        #expect(decl.hasUserGen == false)
    }

    @Test
    func capturesMultiBindingStoredPropertiesAsSeparateMembers() throws {
        let source = """
        struct Pair {
            let lhs: Int, rhs: String
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.storedMembers == [
            StoredMember(name: "lhs", typeName: "Int"),
            StoredMember(name: "rhs", typeName: "String")
        ])
    }

    @Test
    func skipsComputedAndStaticPropertiesFromStoredMembers() throws {
        // Computed properties carry an accessor block; static properties
        // are filtered before binding inspection. Both must be excluded
        // from the strategist's stored-property list.
        let source = """
        struct Bag {
            let raw: Int
            static let empty: Bag = Bag(raw: 0)
            var doubled: Int { raw * 2 }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.storedMembers.map(\.name) == ["raw"])
    }

    @Test
    func capturesHasUserInitOnStructWithExplicitInit() throws {
        let source = """
        struct Wallet {
            let balance: Int
            init(balance: Int) {
                self.balance = balance
            }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.hasUserInit == true)
        // hasUserInit doesn't affect storedMembers — the strategist
        // gates membersise derivation on the conjunction at decision time.
        #expect(decl.storedMembers.map(\.name) == ["balance"])
    }

    @Test
    func extensionWithInitDoesNotSetHasUserInitOnTheExtensionRecord() throws {
        // Inits in extensions don't suppress the synthesised memberwise
        // init per the strategist contract — the extension's TypeDecl
        // must report hasUserInit = false even when its body has an init.
        let source = """
        struct Foo {
            let n: Int
        }
        extension Foo {
            init(double n: Int) {
                self.init(n: n * 2)
            }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let primary = try #require(corpus.typeDecls.first { $0.kind == .struct })
        let extn = try #require(corpus.typeDecls.first { $0.kind == .extension })
        #expect(primary.hasUserInit == false)
        #expect(extn.hasUserInit == false)
        // Extensions never carry stored members either — Swift won't
        // even compile a stored property in an extension.
        #expect(extn.storedMembers.isEmpty)
    }

    @Test
    func capturesHasUserGenOnStaticGenMethod() throws {
        let source = """
        struct Widget {
            let id: Int
            static func gen() -> Gen<Widget> {
                Gen.always(Widget(id: 0))
            }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.hasUserGen == true)
    }

    @Test
    func instanceLevelGenMethodDoesNotSetHasUserGen() throws {
        // A non-static `func gen()` is an instance method, not a
        // factory — strategist Strategy A only honours `static` so the
        // scanner's flag must too.
        let source = """
        struct Widget {
            let id: Int
            func gen() -> Int { id }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.hasUserGen == false)
    }

    @Test
    func extensionWithStaticGenMethodSetsHasUserGenOnExtensionRecord() throws {
        let source = """
        struct Widget {
            let id: Int
        }
        extension Widget {
            static func gen() -> Gen<Widget> { Gen.always(Widget(id: 0)) }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let primary = try #require(corpus.typeDecls.first { $0.kind == .struct })
        let extn = try #require(corpus.typeDecls.first { $0.kind == .extension })
        #expect(primary.hasUserGen == false)
        #expect(extn.hasUserGen == true)
    }
}
