@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// A word inside quotes is not a free name: a guard returning a word literal was invisible to
/// `GuardDomainReader`.
@Suite("guard-domain — word literals")
struct GuardDomainLiteralTests {

    private func read(_ source: String) -> GuardDomain? {
        let tree = Parser.parse(source: source)
        guard let function = tree.statements.first?.item.as(FunctionDeclSyntax.self) else { return nil }
        return GuardDomainReader.read(function)
    }

    @Test("a guard returning a word literal is read, and an interpolated free name still is not")
    func wordLiteralIsAdmitted() throws {
        let early = try #require(read("""
            func label(_ raw: String) -> String {
                if raw.isEmpty { return "unknown" }
                return raw
            }
            """))
        #expect(early.returnedExpression == #""unknown""#)
        #expect(read("""
            func label(_ raw: String) -> String {
                if raw.isEmpty { return "\\(other)" }
                return raw
            }
            """) == nil)
    }
}
