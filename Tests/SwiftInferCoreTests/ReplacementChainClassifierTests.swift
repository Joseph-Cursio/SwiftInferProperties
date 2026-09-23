@testable import SwiftInferCore
import Testing

/// The replacement-chain arm of `IdempotenceReturnShape`: an escaper that re-escapes its own output.
///
/// The cases are the census's (`docs/measurements/replacement-chain-idempotence-census.md`): the real
/// escapers that re-escape, the real sanitisers that do not, and the `x → y → z` chain that the
/// obvious text rule gets wrong — which is why the classifier evaluates rather than inspects.
@Suite("ReplacementChainClassifier — does a second application rewrite again?")
struct ReplacementChainClassifierTests {

    /// A one-function source whose body is `body`, over the parameter `t`.
    private func function(_ body: String) -> String {
        "enum E {\n    static func f(_ t: String) -> String {\n        \(body)\n    }\n}"
    }

    private func shape(_ source: String) throws -> IdempotenceReturnShape? {
        let summaries = FunctionScanner.scanCorpus(source: source, file: "S.swift").summaries
        return try #require(summaries.first).bodySignals.idempotenceReturnShape
    }

    @Test("an HTML escaper re-escapes its own `&`")
    func htmlEscaperReapplies() throws {
        let result = try shape("""
        enum HTMLEscaping {
            static func escape(_ text: String) -> String {
                text.replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
            }
        }
        """)
        guard case let .reappliesItsRewrite(witness) = result else {
            Issue.record("expected .reappliesItsRewrite, got \(String(describing: result))")
            return
        }
        // The witness is a real counterexample, checked against the chain itself.
        let steps = [
            ReplacementChainClassifier.Step(pattern: "&", replacement: "&amp;"),
            ReplacementChainClassifier.Step(pattern: "<", replacement: "&lt;")
        ]
        let once = ReplacementChainClassifier.apply(steps, to: witness)
        #expect(ReplacementChainClassifier.apply(steps, to: once) != once)
    }

    @Test("a quote escaper that emits a quote re-escapes, with an explicit return")
    func quoteEscaperReapplies() throws {
        let result = try shape(function(#"return t.replacingOccurrences(of: "\"", with: "\\\"")"#))
        guard case .reappliesItsRewrite = result else {
            Issue.record("expected .reappliesItsRewrite, got \(String(describing: result))")
            return
        }
    }

    /// **The controls.** Each is a real, idempotent chain; a veto on any would withdraw a true law.
    @Test("sanitisers and a later step rewriting an earlier output stay unvetoed",
          arguments: [
            // `mermaidEscape`: its entities contain none of the characters it escapes.
            #"t.replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "|", with: "&#124;")"#,
            // `x → y → z`: an output contains a LATER pattern, rewritten later in the same pass.
            #"t.replacingOccurrences(of: "x", with: "y").replacingOccurrences(of: "y", with: "z")"#,
            // `safeAlias`-style: whitespace and punctuation to underscores.
            #"t.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")"#
          ])
    func idempotentChainsStayQuiet(body: String) throws {
        #expect(try shape(function(body)) == .notExtending)
    }

    @Test("a chain that is not the whole body, or not on the parameter, is not read",
          arguments: [
            #"t.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "&", with: "&amp;")"#,
            #"String(t.reversed()).replacingOccurrences(of: "&", with: "&amp;")"#
          ])
    func onlyAPureChainOnTheInput(body: String) throws {
        #expect(try shape(function(body)) == .notExtending)
    }

    @Test("a computed property on String that re-escapes is caught through implicit self")
    func propertyEscaperReapplies() throws {
        let summaries = FunctionScanner.scanCorpus(source: """
        extension String {
            var xmlEscaped: String {
                replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: ">", with: "&gt;")
            }
            var count2: Int { count }
        }
        """, file: "S.swift").summaries
        let escaped = try #require(summaries.first { $0.name == "xmlEscaped" })
        let escapedShape = escaped.bodySignals.idempotenceReturnShape
        guard case .reappliesItsRewrite = escapedShape else {
            Issue.record("expected .reappliesItsRewrite, got \(String(describing: escapedShape))")
            return
        }
        // A property of another type is not the self-form and gets no shape at all.
        let other = try #require(summaries.first { $0.name == "count2" })
        #expect(other.bodySignals.idempotenceReturnShape == nil)
    }
}
