@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// guard-domain's free-name gate reads the syntax, not the text
/// (`docs/measurements/guard-domain-syntax-gate.md`).
///
/// A label, a member, a closure's own parameter and a word inside a string literal are not names. `super`,
/// a macro, a type in a condition and a `$`-projection are.
@Suite("guard-domain — the free-name gate reads syntax")
struct GuardDomainSyntaxGateTests {

    private func read(_ source: String) -> GuardDomain? {
        let finder = GuardDomainReaderTests.Finder(viewMode: .sourceAccurate)
        finder.walk(Parser.parse(source: source))
        return finder.found.flatMap(GuardDomainReader.read)
    }

    /// MacCloud_server's `File.canAccess(user:)`: `$user` is the model's projection, state of the receiver. The
    /// text gate read it as the parameter `user` and admitted a law about the object.
    @Test func aProjectionIsNotTheParameter() {
        #expect(read("""
        func canAccess(user: User) -> Bool {
            if user.id == $user.id {
                return true
            }
            return false
        }
        """) == nil)
    }

    /// swift-format's `visit(_:)`: a test cannot call `super`.
    @Test func superIsFree() {
        #expect(read("""
        func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
            if node.arguments.count == 0 { return super.visit(node) }
            return ExprSyntax(node)
        }
        """) == nil)
    }

    /// swift-format's `AlwaysUseLowerCamelCase.visit(_:)`: `anyOf` is a label, not a name.
    @Test func aLabelledCallIsAdmitted() throws {
        let domain = try #require(read("""
        func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            if node.modifiers.contains(anyOf: [.override]) {
                return .visitChildren
            }
            return .skipChildren
        }
        """))
        #expect(domain.condition == "node.modifiers.contains(anyOf: [.override])")
        #expect(domain.returnedExpression == ".visitChildren")
    }

    /// pbt-workbook-corpus's `describe(_:)`: `item` is a word in the literal; `count` in the interpolation is
    /// the parameter.
    @Test func aWordInsideAnInterpolatedLiteralIsNotAName() throws {
        let domain = try #require(read("""
        func describe(_ count: Int) -> String {
            if count == 1 { return "\\(count) item" }
            return "\\(count) items"
        }
        """))
        #expect(domain.returnedExpression == #""\(count) item""#)
    }

    /// An interpolation is still code: a name in it that is not the parameter refuses the site.
    @Test func aNameInsideAnInterpolationIsStillFree() {
        #expect(read("""
        func describe(_ count: Int) -> String {
            if count == 1 { return "\\(unit) item" }
            return "\\(count) items"
        }
        """) == nil)
    }

    /// A closure's parameters, shorthand or named, are bound by the closure.
    @Test func aClosuresOwnParametersAreBound() throws {
        let shorthand = #"node.arguments.contains(where: { $0.label?.text == "x" })"#
        #expect(GuardDomainReader.mentionsOnly("node", in: shorthand))
        #expect(GuardDomainReader.mentionsOnly("values", in: "values.contains { value in value > 0 }"))
        #expect(!GuardDomainReader.mentionsOnly("values", in: "values.contains { value in value > limit }"))
    }

    /// The gate's other rules are unchanged: a helper, a type in a condition and a macro are free.
    @Test func helpersTypesAndMacrosAreStillFree() {
        #expect(!GuardDomainReader.mentionsOnly("value", in: "isValidValue(value)"))
        #expect(!GuardDomainReader.mentionsOnly("value", in: "value is Marker"))
        #expect(!GuardDomainReader.mentionsOnly("line", in: "line == #line"))
        #expect(GuardDomainReader.mentionsOnly("value", in: "Marker(value)", allowingTypeNames: true))
        #expect(GuardDomainReader.mentionsOnly("value", in: "self.isEmpty || Self.limit < value.count"))
    }

    /// The writer agrees: `$user` is unbound even when `user` is bound.
    @Test func theWriterDoesNotRebindAProjection() {
        let bindings = ["user": "arg0"]
        #expect(GuardDomainRebinding.unboundNames(in: "user.id == $user.id", bindings: bindings) == ["$user"])
        #expect(GuardDomainRebinding.rebind("user.id == $user.id", bindings: bindings) == nil)
        #expect(GuardDomainRebinding.rebind("user.items.contains { $0 > 1 }", bindings: bindings)
            == "arg0.items.contains { $0 > 1 }")
    }
}
