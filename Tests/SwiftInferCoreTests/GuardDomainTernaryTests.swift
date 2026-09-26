@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// A body that is one ternary states the same law as an early return, and `GuardDomainReader` read
/// only the statement forms.
@Suite("guard-domain — a ternary body")
struct GuardDomainTernaryTests {

    private func read(_ source: String) -> GuardDomain? {
        let tree = Parser.parse(source: source)
        guard let function = tree.statements.first?.item.as(FunctionDeclSyntax.self) else { return nil }
        return GuardDomainReader.read(function)
    }

    @Test("a ternary swapping one literal is its then-branch's law")
    func ternaryThenBranch() throws {
        let source = #"func renderStateToken(_ name: String) -> String { name == "*" ? "[*]" : name }"#
        let domain = try #require(read(source))
        #expect(domain.condition == #"name == "*""#)
        #expect(domain.returnedExpression == #""[*]""#)
        #expect(domain.firesWhenConditionHolds)
    }

    @Test("a ternary swapping in a word literal is read — the literal's letters are not free names")
    func wordLiteralTernary() throws {
        let source = #"func sanitizeLabel(_ raw: String) -> String { return raw.isEmpty ? "relates" : raw }"#
        let ternary = try #require(read(source))
        #expect(ternary.returnedExpression == #""relates""#)
    }

    @Test("when the then-branch is the parameter, the else-branch is the law, firing when the condition fails")
    func ternaryElseBranch() throws {
        let source = #"func fileURI(_ path: String) -> String { path.hasPrefix("/") ? path : "none" }"#
        let domain = try #require(read(source))
        #expect(domain.returnedExpression == #""none""#)
        #expect(!domain.firesWhenConditionHolds)
    }

    /// A nested ternary in the returned branch is admitted: `x > 0 ⟹ f(x) == (x > 9 ? 9 : 1)` names only
    /// the parameter and literals, so it is a law a test can state.
    @Test("a helper call, an interpolation of a free name, or a longer body is not read")
    func refusals() {
        #expect(read(#"func f(_ x: String) -> String { isOK(x) ? "a" : x }"#) == nil)
        #expect(read(#"func f(_ x: String) -> String { x.isEmpty ? "\(other)" : x }"#) == nil)
        #expect(read("""
            func f(_ x: String) -> String {
                let y = x
                return y.isEmpty ? "a" : y
            }
            """) == nil)
    }
}
