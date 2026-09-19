import Foundation
@testable import SwiftInferCore
import Testing

/// What counts as a snippet: a multi-line, interpolation-free literal that parses cleanly.
@Suite("Syntax snippets — harvested from a package's tests")
struct SyntaxSnippetHarvesterTests {

    private static let testFile = #"""
    import Testing

    @Test func flagsAForceUnwrap() {
        let source = """
        func load() -> Int { value! }
        """
        let message = "not a snippet"
        let templated = """
        struct \(name) {}
        """
        let broken = """
        func (((
        """
        _ = (source, message, templated, broken)
    }
    """#

    @Test("only a clean, interpolation-free multi-line literal is kept")
    func whatCounts() {
        let literals = SyntaxSnippetHarvester.multiLineLiterals(in: Self.testFile)
        // The interpolated literal is dropped by the harvester; the broken one survives to here
        // and is dropped by the parse check below.
        #expect(literals == ["func load() -> Int { value! }", "func (((" ])
        #expect(SyntaxSnippetHarvester.parsesCleanly(literals[0]))
        #expect(!SyntaxSnippetHarvester.parsesCleanly(literals[1]))
    }

    @Test("the corpus records the node types it can produce, bases included")
    func nodeTypes() {
        let corpus = SyntaxSnippetHarvester.corpus(of: ["func load() -> Int { value! }"])
        for name in ["Syntax", "FunctionDeclSyntax", "DeclSyntax", "ForceUnwrapExprSyntax", "ExprSyntax"] {
            #expect(corpus.nodeTypeNames.contains(name), "missing \(name)")
        }
        #expect(!corpus.nodeTypeNames.contains("ClassDeclSyntax"))
    }

    @Test("harvesting a directory keeps clean snippets once each, in path order")
    func harvestDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("snippet-harvest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(Self.testFile.utf8).write(to: root.appendingPathComponent("B.swift"))
        try Data(Self.testFile.utf8).write(to: root.appendingPathComponent("A.swift"))
        let corpus = SyntaxSnippetHarvester.harvest(roots: [root])
        #expect(corpus.snippets == ["func load() -> Int { value! }"])
    }
}
