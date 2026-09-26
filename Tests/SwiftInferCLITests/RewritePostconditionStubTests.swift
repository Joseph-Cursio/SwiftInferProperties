@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// An accepted `rewrite-postcondition` suggestion writes a stub stating what the rewrite removes.
@Suite("rewrite-postcondition — the stub writer")
struct RewritePostconditionStubTests {

    private static func stub(_ source: String) throws -> String {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Script.swift")
        let suggestion = try #require(TemplateRegistry.discover(in: corpus.summaries, typeDecls: corpus.typeDecls)
            .first { $0.templateName == "rewrite-postcondition" })
        return try #require(InteractiveTriage.templateStub(for: suggestion))
    }

    @Test("a replacement chain's stub checks every removed token, newlines escaped")
    func chainStub() throws {
        let text = try Self.stub("""
            enum Script {
                static func safeAlias(_ name: String) -> String {
                    name.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: "\\n", with: "_")
                }
            }
            """)
        #expect(text.contains(#"!result.contains("-") && !result.contains("\n")"#), "got:\n\(text)")
        #expect(text.contains("Script.safeAlias(value)"))
    }

    @Test("a split's stub checks no element contains the separator")
    func splitStub() throws {
        let text = try Self.stub("""
            func parseList(_ string: String) -> [String] {
                string.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
            """)
        #expect(text.contains(#"!result.contains { $0.contains(",") }"#), "got:\n\(text)")
    }
}
