@testable import SwiftInferCLI
import Testing

/// The edit line in a restricted stub's header names every keyword to delete.
///
/// Before this, the header read the declaration's own line alone: for a `private` member of a
/// `private` class it named the member's keyword one line below a remedy calling that edit a no-op,
/// and for a member of a `private extension` it named nothing while pointing at a `public` type.
@Suite("Access caveat — the edit names every blocking keyword")
struct AccessCaveatEditTests {

    @Test("a private member of a private class names both keywords")
    func bothKeywords() {
        let source = """
        struct LoggingSensitiveDataVisitor {
            private final class SensitiveReferenceFinder {
                private func containsSensitiveWord(_ name: String) -> Bool { true }
            }
        }
        """
        let edit = InteractiveTriage.widenTarget(fileName: "Visitor.swift", line: 3, source: source)
        #expect(edit == "Delete `private` at Visitor.swift:2 (`class SensitiveReferenceFinder`) and "
            + "`private` at Visitor.swift:3 (the declaration), or lift the logic out.")
    }

    @Test("a private extension is named, with the narrower alternative")
    func privateExtension() throws {
        let source = """
        public struct ERScript {}
        private extension ERScript {
            static func sanitizeType(_ raw: String) -> String { raw }
        }
        """
        let edit = try #require(InteractiveTriage.widenTarget(fileName: "ERScript.swift", line: 3, source: source))
        #expect(edit.hasPrefix("Delete `private` at ERScript.swift:2 (`extension ERScript`)"))
        #expect(edit.contains("widens every member of that extension"))
        #expect(edit.contains("moving this declaration into an unmarked extension widens only it"))
    }

    /// **The control**: the one-keyword case keeps its exact sentence, so the census's widen-ready
    /// selection and every stub already written read the same.
    @Test("a declaration-only restriction keeps the original sentence")
    func declarationOnly() {
        let source = """
        enum IdempotencyTestsMacro {
            private static func isCallableWithNoArguments(_ text: String) -> Bool { true }
        }
        """
        #expect(InteractiveTriage.widenTarget(fileName: "Macro.swift", line: 2, source: source)
            == "Delete `private` at Macro.swift:2, or lift the logic out.")
    }

    @Test("an unrestricted declaration gets no edit")
    func unrestricted() {
        let source = "struct Open {\n    func run() {}\n}\n"
        #expect(InteractiveTriage.widenTarget(fileName: "Open.swift", line: 2, source: source) == nil)
    }
}
