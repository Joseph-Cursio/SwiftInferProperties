@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// Which tokens a string-rewriting body removes — decided by evaluating the chain, and refused for
/// a split whose closure could put the separator back.
@Suite("rewrite-postcondition — what a rewrite removes")
struct RewritePostconditionTests {

    private func read(_ source: String) -> RewritePostcondition? {
        let tree = Parser.parse(source: source)
        guard let function = tree.statements.first?.item.as(FunctionDeclSyntax.self) else { return nil }
        return RewritePostconditionReader.read(function)
    }

    @Test("a chain replacing each token with one it cannot contain lacks every token")
    func safeAlias() {
        let found = read("""
            func safeAlias(_ name: String) -> String {
                name.replacingOccurrences(of: "-", with: "_")
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: ".", with: "_")
            }
            """)
        #expect(found?.guarantee == .outputLacks(["-", " ", "."]))
    }

    @Test("a later step that reintroduces an earlier pattern keeps it out of the law")
    func reintroducedPattern() {
        let found = read("""
            func f(_ x: String) -> String {
                x.replacingOccurrences(of: "a", with: "b").replacingOccurrences(of: "b", with: "a")
            }
            """)
        #expect(found?.guarantee == .outputLacks(["b"]))
    }

    /// Removing an inner `<mark>` from `<ma<mark>rk>` forms a new one, so a multi-character pattern is
    /// never claimed — the census's `stripMarkTags` was a false law under the first, search-based rule.
    @Test("a multi-character pattern is never claimed")
    func multiCharacterPattern() {
        let source = #"func strip(_ s: String) -> String { s.replacingOccurrences(of: "<mark>", with: "") }"#
        #expect(read(source) == nil)
    }

    @Test("an escaper whose replacement contains its pattern states nothing")
    func escaper() {
        let source = #"func escape(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;") }"#
        #expect(read(source) == nil)
    }

    @Test("a split whose elements are only trimmed or dropped lacks the separator")
    func trimmedSplit() {
        let found = read("""
            func parseCommaDelimitedList(_ string: String) -> [String] {
                string.components(separatedBy: ",").compactMap {
                    let item = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    return item.isEmpty ? nil : item
                }
            }
            """)
        #expect(found?.guarantee == .elementsLack(","))
    }

    @Test("a split whose closure could write the separator back, or any other return type, states nothing")
    func refusals() {
        #expect(read(#"func f(_ s: String) -> [String] { s.components(separatedBy: ",").map { $0 + "," } }"#) == nil)
        #expect(read(#"func f(_ s: String) -> [String] { s.components(separatedBy: ",").map { wrap($0) } }"#) == nil)
        #expect(read(#"func f(_ s: String) -> Int { s.replacingOccurrences(of: "-", with: "").count }"#) == nil)
    }
}
