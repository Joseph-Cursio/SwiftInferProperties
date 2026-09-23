@testable import SwiftInferCore
import Testing

/// The subject's own string literals — the tokens the kit's `String` generators draw alongside
/// their curated ones. The shapes are the two the measurement found: an escaper whose idempotence
/// law was false, and the Markdown parser that looped forever on its own `"#"`.
@Suite("SubjectLiterals — a subject's own tokens")
struct SubjectLiteralsTests {

    @Test("an escaper's patterns and entities, in source order")
    func escaperLiterals() {
        let source = """
        enum HTMLEscaping {
            static func escape(_ text: String) -> String {
                text.replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
            }
        }
        """
        #expect(SubjectLiterals.harvest(declarationAt: 2, in: source) == ["&", "&amp;", "<", "&lt;"])
    }

    /// The parser whose `"#"` hung it: every delimiter it tests for, including inside nested loops.
    @Test("a parser's delimiters, deduplicated")
    func parserDelimiters() {
        let source = #"""
        struct Doc {
            func parseBlocks(_ text: String) -> [String] {
                let lines = text.components(separatedBy: "\n")
                for line in lines {
                    if line.hasPrefix("[←") { continue }
                    if line.hasPrefix("```") { continue }
                    while line.hasPrefix("#") || line == "---" || line.hasPrefix("```") { break }
                }
                return lines
            }
        }
        """#
        // Line 2 is the function's declaration, which is what a suggestion's evidence points at. A
        // line INSIDE the body names the innermost declaration there — here the local `let lines` —
        // so the harvest is of the declaration the line starts, not of whatever encloses it.
        #expect(SubjectLiterals.harvest(declarationAt: 2, in: source) == ["\n", "[←", "```", "#", "---"])
        #expect(SubjectLiterals.harvest(declarationAt: 3, in: source) == ["\n"])
    }

    @Test("interpolated, empty and prose-length literals are not tokens")
    func exclusions() {
        let source = #"""
        enum E {
            static func f(_ name: String) -> String {
                if name.isEmpty { return "" }
                let message = "This literal is much too long to be a token anyone would draw as input"
                return "hello \(name)" + message + ";"
            }
        }
        """#
        #expect(SubjectLiterals.harvest(declarationAt: 2, in: source) == [";"])
    }

    @Test("a line in no declaration yields nothing, and so does an unreadable file")
    func nothingToHarvest() {
        #expect(SubjectLiterals.harvest(declarationAt: 1, in: "import Foundation\nlet x = \"a\"\n").isEmpty)
    }

    @Test("the list is capped")
    func capped() {
        let literals = (0..<30).map { "\"t\($0)\"" }.joined(separator: ", ")
        let source = "enum E {\n    static func f() -> [String] {\n        [\(literals)]\n    }\n}"
        let harvested = SubjectLiterals.harvest(declarationAt: 2, in: source)
        #expect(harvested.count == SubjectLiterals.cap)
        #expect(harvested.first == "t0")
    }
}
