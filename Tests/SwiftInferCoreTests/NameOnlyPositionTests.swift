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
        #expect(try Self.reference("name", in: #"rows.map(\.name)"#).isNameOnlyPosition(members: .anyBase))
        #expect(try Self.reference("name", in: #"rows.map(\.name)"#).isNameOnlyPosition(members: .otherThanSelf))
    }

    /// `index` is evaluated when the key path is formed, so it reads a binding like any argument.
    @Test("a key-path subscript component's argument is a read")
    func keyPathSubscriptArgumentIsARead() throws {
        let index = try Self.reference("index", in: #"rows.map(\.[index])"#)
        #expect(!index.isKeyPathComponentName)
        #expect(!index.isNameOnlyPosition(members: .anyBase))
    }

    @Test("a member name is name-only on any base; the base is a read")
    func memberNames() throws {
        #expect(try Self.reference("name", in: "job.name").isMemberName(on: .anyBase))
        #expect(try Self.reference("name", in: "job.name").isMemberName(on: .otherThanSelf))
        #expect(try Self.reference("pattern", in: "Rule().pattern").isMemberName(on: .otherThanSelf))
        #expect(try Self.reference("id", in: "rows.map { $0.id }").isMemberName(on: .otherThanSelf))
        let base = try Self.reference("job", in: "job.name")
        #expect(!base.isMemberName(on: .anyBase))
        #expect(!base.isNameOnlyPosition(members: .anyBase))
        #expect(!base.isKeyPathComponentName)
    }

    /// A leading-dot member has no base at all, so it is never "on `self`".
    @Test("a leading-dot member is name-only under either scope")
    func leadingDotMember() throws {
        let red = try Self.reference("red", in: "paint(.red)")
        #expect(red.isMemberName(on: .anyBase))
        #expect(red.isMemberName(on: .otherThanSelf))
        #expect(!red.isKeyPathComponentName)
    }

    /// The one place the two scopes differ: `self.name` is the stored property `name` spelled
    /// out, and `.otherThanSelf` is for readers that keep it as one.
    @Test("a member of self is name-only under .anyBase only")
    func memberOfSelf() throws {
        let name = try Self.reference("name", in: "self.name")
        #expect(name.isMemberName(on: .anyBase))
        #expect(!name.isMemberName(on: .otherThanSelf))
        #expect(!name.isNameOnlyPosition(members: .otherThanSelf))
        #expect(name.isNameOnlyPosition(members: .anyBase))
    }

    @Test("a bare reference and a call's callee are reads")
    func bareReferencesAreReads() throws {
        let call = "sortItems(items)"
        for text in ["sortItems", "items"] {
            let node = try Self.reference(text, in: call)
            #expect(!node.isNameOnlyPosition(members: .anyBase), "`\(text)` in `\(call)`")
        }
    }
}
