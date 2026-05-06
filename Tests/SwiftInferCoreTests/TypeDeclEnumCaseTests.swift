import Foundation
import Testing
@testable import SwiftInferCore

@Suite("TypeDecl.enumCaseNames — case-extraction shapes (M14.0)")
struct TypeDeclEnumCaseTests {

    // MARK: - Bare cases

    @Test("Single bare case → one entry")
    func singleBareCase() throws {
        let corpus = FunctionScanner.scanCorpus(source: """
            enum Color {
                case red
            }
            """, file: "T.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.enumCaseNames == ["red"])
    }

    @Test("Three bare cases on separate lines → entries in source order")
    func threeBareCasesSeparateLines() throws {
        let corpus = FunctionScanner.scanCorpus(source: """
            enum Size {
                case small
                case medium
                case large
            }
            """, file: "T.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.enumCaseNames == ["small", "medium", "large"])
    }

    @Test("Multi-binding case → one entry per binding, source order preserved")
    func multiBindingCase() throws {
        let corpus = FunctionScanner.scanCorpus(source: """
            enum Size {
                case small, medium, large
            }
            """, file: "T.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.enumCaseNames == ["small", "medium", "large"])
    }

    // MARK: - Associated-value + raw-value stripping

    @Test("Associated-value cases → identifier only (parameter clause stripped)")
    func associatedValueCasesStripped() throws {
        let corpus = FunctionScanner.scanCorpus(source: """
            enum Result {
                case success(Int)
                case failure(Error)
            }
            """, file: "T.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.enumCaseNames == ["success", "failure"])
    }

    @Test("Raw-value cases → identifier only (raw value stripped)")
    func rawValueCasesStripped() throws {
        let corpus = FunctionScanner.scanCorpus(source: """
            enum Direction: String {
                case north = "N"
                case south = "S"
            }
            """, file: "T.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.enumCaseNames == ["north", "south"])
    }

    // MARK: - Empty + non-enum kinds

    @Test("Enum with no declared cases → empty enumCaseNames")
    func emptyEnumYieldsEmptyList() throws {
        let corpus = FunctionScanner.scanCorpus(source: """
            enum Empty {}
            """, file: "T.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.enumCaseNames.isEmpty)
    }

    @Test("Struct kind → enumCaseNames is empty (only enums populate)")
    func structKindNotPopulated() throws {
        let corpus = FunctionScanner.scanCorpus(source: """
            struct Box {
                let value: Int
            }
            """, file: "T.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.enumCaseNames.isEmpty)
    }

    @Test("Class kind → enumCaseNames is empty")
    func classKindNotPopulated() throws {
        let corpus = FunctionScanner.scanCorpus(source: """
            class Counter {
                var count = 0
            }
            """, file: "T.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.enumCaseNames.isEmpty)
    }

    @Test("Actor kind → enumCaseNames is empty")
    func actorKindNotPopulated() throws {
        let corpus = FunctionScanner.scanCorpus(source: """
            actor Bank {
                var balance = 0
            }
            """, file: "T.swift")
        let decl = try #require(corpus.typeDecls.first)
        #expect(decl.enumCaseNames.isEmpty)
    }

    // MARK: - Extension-declared cases

    @Test("Extension on an enum that adds cases populates the extension's enumCaseNames")
    func extensionAddingCases() throws {
        let corpus = FunctionScanner.scanCorpus(source: """
            enum Size {
                case small
            }
            extension Size {
                case medium, large
            }
            """, file: "T.swift")
        let primary = try #require(corpus.typeDecls.first { $0.kind == .enum && $0.name == "Size" })
        let ext = try #require(corpus.typeDecls.first { $0.kind == .extension && $0.name == "Size" })
        #expect(primary.enumCaseNames == ["small"])
        #expect(ext.enumCaseNames == ["medium", "large"])
    }

    @Test("Extension on a struct does NOT populate enumCaseNames (no `case` decls expected)")
    func extensionOnStructEmpty() throws {
        let corpus = FunctionScanner.scanCorpus(source: """
            struct Box { let v: Int }
            extension Box {
                func helper() -> Int { v }
            }
            """, file: "T.swift")
        let ext = try #require(corpus.typeDecls.first { $0.kind == .extension && $0.name == "Box" })
        #expect(ext.enumCaseNames.isEmpty)
    }

    // MARK: - Init back-compat

    @Test("Init with all fields preserves new enumCaseNames field")
    func initRoundTrip() {
        let decl = TypeDecl(
            name: "Size",
            kind: .enum,
            inheritedTypes: ["Equatable"],
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            enumCaseNames: ["small", "medium", "large"]
        )
        #expect(decl.enumCaseNames == ["small", "medium", "large"])
    }

    @Test("Default init produces empty enumCaseNames (back-compat with M13.x callers)")
    func defaultInitYieldsEmpty() {
        let decl = TypeDecl(
            name: "Anonymous",
            kind: .struct,
            inheritedTypes: [],
            location: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        #expect(decl.enumCaseNames.isEmpty)
    }
}
