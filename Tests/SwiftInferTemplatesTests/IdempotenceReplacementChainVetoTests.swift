import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `idempotence` is withdrawn for an escaper that re-escapes, and kept for one that does not.
///
/// The two halves are one claim: the veto costs no true law.
/// `docs/measurements/replacement-chain-idempotence-census.md` found 5 re-escaping chains and 5
/// idempotent ones, and a gate that fired on both would have traded five false laws for five true ones.
@Suite("Idempotence — the replacement-chain veto")
struct IdempotenceReplacementChainVetoTests {

    private func suggestion(_ source: String) throws -> Suggestion? {
        let summary = try #require(FunctionScanner.scanCorpus(source: source, file: "S.swift").summaries.first)
        return IdempotenceTemplate.suggest(for: summary)
    }

    @Test("a re-escaping chain is not proposed idempotence")
    func reEscaperWithdrawn() throws {
        #expect(try suggestion("""
        enum HTMLEscaping {
            static func escape(_ text: String) -> String {
                text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            }
        }
        """) == nil)
    }

    @Test("an idempotent chain still is — the control")
    func idempotentChainKept() throws {
        #expect(try suggestion(#"""
        enum M {
            static func mermaidEscape(_ t: String) -> String {
                t.replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "|", with: "&#124;")
            }
        }
        """#) != nil)
    }
}
