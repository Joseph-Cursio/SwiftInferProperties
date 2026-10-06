import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// A `DeclReferenceExprSyntax` that is only a NAME — a key-path component's, or a member's —
/// against one that reads a binding.
@Suite("DeclReferenceExprSyntax — name-only positions")
struct NameOnlyPositionTests {

    /// Every `DeclReferenceExprSyntax` in `expression`, in source order, by its spelling.
    private static func references(in expression: String) -> [(text: String, node: DeclReferenceExprSyntax)] {
        let collector = ReferenceCollector(viewMode: .sourceAccurate)
        collector.walk(Parser.parse(source: "_ = \(expression)"))
        return collector.found.map { ($0.baseName.text, $0) }
    }

    /// The single reference spelled `text` in `expression`.
    private static func reference(_ text: String, in expression: String) throws -> DeclReferenceExprSyntax {
        let matches = references(in: expression).filter { $0.text == text }
        try #require(matches.count == 1, "expected one `\(text)` in `\(expression)`, found \(matches.count)")
        return matches[0].node
    }

    private final class ReferenceCollector: SyntaxVisitor {
        var found: [DeclReferenceExprSyntax] = []

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            found.append(node)
            return .visitChildren
        }
    }

    @Test("a key-path property component's name is name-only, at any depth and under a root type")
    func keyPathComponentNames() throws {
        #expect(try Self.reference("name", in: #"rows.map(\.name)"#).isKeyPathComponentName)
        #expect(try Self.reference("name", in: #"\Job.name"#).isKeyPathComponentName)
        let nested = #"rows.map(\.owner.name)"#
        #expect(try Self.reference("owner", in: nested).isKeyPathComponentName)
        #expect(try Self.reference("name", in: nested).isKeyPathComponentName)
        let name = try Self.reference("name", in: #"rows.map(\.name)"#)
        #expect(name.isNameOnlyPosition)
        #expect(!name.isMemberName)
        #expect(!name.isImplicitMemberName)
    }

    /// `index` is evaluated when the key path is formed, so it reads a binding like any argument.
    @Test("a key-path subscript component's argument is a read")
    func keyPathSubscriptArgumentIsARead() throws {
        let index = try Self.reference("index", in: #"rows.map(\.[index])"#)
        #expect(!index.isKeyPathComponentName)
        #expect(!index.isNameOnlyPosition)
    }

    @Test("a member name is name-only on any base, self included; the base is a read")
    func memberNames() throws {
        for (text, expression) in [
            ("name", "job.name"), ("pattern", "Rule().pattern"), ("id", "rows.map { $0.id }"),
            ("name", "self.name"), ("name", "self?.name"), ("name", "Self.name")
        ] {
            let node = try Self.reference(text, in: expression)
            #expect(node.isMemberName, "`\(text)` in `\(expression)`")
            #expect(node.isNameOnlyPosition, "`\(text)` in `\(expression)`")
            #expect(!node.isImplicitMemberName, "`\(text)` in `\(expression)`")
        }
        let base = try Self.reference("job", in: "job.name")
        #expect(!base.isMemberName)
        #expect(!base.isNameOnlyPosition)
        #expect(!base.isKeyPathComponentName)
    }

    /// A leading-dot member has no base at all: its type comes from the context.
    @Test("a leading-dot member is an implicit member name")
    func leadingDotMember() throws {
        let red = try Self.reference("red", in: "paint(.red)")
        #expect(red.isMemberName)
        #expect(red.isImplicitMemberName)
        #expect(red.isNameOnlyPosition)
        #expect(!red.isKeyPathComponentName)
    }

    @Test("a bare reference and a call's callee are reads")
    func bareReferencesAreReads() throws {
        let call = "sortItems(items)"
        for text in ["sortItems", "items"] {
            let node = try Self.reference(text, in: call)
            #expect(!node.isNameOnlyPosition, "`\(text)` in `\(call)`")
        }
    }
}
