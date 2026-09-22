import SwiftInferCore
import Testing

/// Every keyword between a test and a declaration, found where it is written.
///
/// The three shapes are the three the 22 September census set aside with access as their first
/// error: a member of a `private` type that is itself `private` (SwiftProjectLint's
/// `SensitiveReferenceFinder`), a member of a `private` type with no keyword of its own
/// (`TypeMemberCollector`), and a member of a `private extension` of a `public` type — all eight of
/// SwiftUMLStudio's.
@Suite("RestrictedScopes — which keywords block a declaration")
struct RestrictedScopesTests {

    @Test("a private member of a private class needs BOTH keywords, outermost first")
    func privateMemberOfPrivateClass() {
        let source = """
        struct LoggingSensitiveDataVisitor {
            private final class SensitiveReferenceFinder {
                private func containsSensitiveWord(_ name: String) -> Bool {
                    name.contains("password")
                }
            }
        }
        """
        let scopes = RestrictedScopes.blocking(declarationAt: 3, in: source)
        #expect(scopes == [
            .init(modifier: "private", line: 2, enclosing: "class SensitiveReferenceFinder"),
            .init(modifier: "private", line: 3, enclosing: nil)
        ])
    }

    @Test("a member of a private extension is blocked by the EXTENSION, not by its public type")
    func memberOfPrivateExtension() {
        let source = """
        public struct ERScript {
            public let text: String
        }

        private extension ERScript {
            static func sanitizeType(_ raw: String) -> String {
                raw.replacingOccurrences(of: " ", with: "_")
            }
        }
        """
        let scopes = RestrictedScopes.blocking(declarationAt: 6, in: source)
        #expect(scopes == [.init(modifier: "private", line: 5, enclosing: "extension ERScript")])
        #expect(scopes.first?.widensSiblings == true)
    }

    @Test("an unmarked member of a fileprivate struct names the struct")
    func unmarkedMemberOfFileprivateStruct() {
        let source = """
        fileprivate struct TypeMemberCollector {
            func isSyntacticValue(_ text: String) -> Bool { !text.isEmpty }
        }
        """
        #expect(RestrictedScopes.blocking(declarationAt: 2, in: source) == [
            .init(modifier: "fileprivate", line: 1, enclosing: "struct TypeMemberCollector")
        ])
    }

    @Test("a declaration-only restriction names the declaration's own keyword")
    func declarationOnly() {
        let source = """
        struct Tokenizer {
            @inlinable
            private static func isCallable(_ text: String) -> Bool { true }
        }
        """
        // The line of the attribute is inside the declaration too, so either line finds it.
        let expected: [RestrictedScopes.Scope] = [.init(modifier: "private", line: 3, enclosing: nil)]
        #expect(RestrictedScopes.blocking(declarationAt: 2, in: source) == expected)
        #expect(RestrictedScopes.blocking(declarationAt: 3, in: source) == expected)
    }

    /// **Controls.** A setter restriction does not stop a test naming anything, and a function
    /// whose name merely begins with `private` is not a `private` declaration.
    @Test("private(set) and a private-prefixed name are not restrictions")
    func notRestrictions() {
        let source = """
        struct Store {
            private(set) var count: Int = 0
            func privateKeyFor(_ id: Int) -> String { "\\(id)" }
        }
        """
        #expect(RestrictedScopes.blocking(declarationAt: 2, in: source).isEmpty)
        #expect(RestrictedScopes.blocking(declarationAt: 3, in: source).isEmpty)
    }

    @Test("a line inside no declaration finds nothing")
    func noDeclaration() {
        #expect(RestrictedScopes.blocking(declarationAt: 1, in: "import Foundation\n").isEmpty)
    }
}
