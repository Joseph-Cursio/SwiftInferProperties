import Foundation
import PropertyLawCore
@testable import SwiftInferCore
import Testing

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
            StoredMember(name: "rhs", typeName: "String"),
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
