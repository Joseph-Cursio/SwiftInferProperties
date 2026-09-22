import Foundation
import SwiftInferCore
import Testing

/// A copied construction brings the imports of the test file it was copied from.
@Suite("ReceiverConstructionHarvester — imports travel with the construction")
struct ReceiverConstructionImportsTests {

    private static func harvest(_ files: [String: String], wanted: Set<String>)
        -> [String: ReceiverConstructionHarvester.Harvested] {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("construction-imports-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (name, text) in files {
            try? text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return ReceiverConstructionHarvester.harvestWithImports(roots: [directory], wanted: wanted)
    }

    @Test("each construction carries its own file's imports, attributes included")
    func importsComeFromTheConstructingFile() throws {
        let found = Self.harvest([
            "VisitorTests.swift": """
            import SwiftParser
            import SwiftProjectLintVisitors
            @testable import SwiftProjectLintRules
            import Testing

            @Test func visits() {
                _ = UnsafeMemoryAPIVisitor(pattern: SyntaxPattern(name: .unsafe))
            }
            """,
            "OtherTests.swift": """
            import Foundation

            @Test func other() {
                _ = Budget(limit: 10)
            }
            """
        ], wanted: ["UnsafeMemoryAPIVisitor", "Budget"])

        let visitor = try #require(found["UnsafeMemoryAPIVisitor"])
        #expect(visitor.imports == [
            "import SwiftParser",
            "import SwiftProjectLintVisitors",
            "@testable import SwiftProjectLintRules",
            "import Testing"
        ])
        #expect(found["Budget"]?.imports == ["import Foundation"])
    }

    /// `harvest` is unchanged: the same expressions, no imports.
    @Test("harvest still returns the bare expressions")
    func harvestIsUnchanged() {
        let found = ReceiverConstructionHarvester.harvest(roots: [], wanted: ["Anything"])
        #expect(found.isEmpty)
    }
}
