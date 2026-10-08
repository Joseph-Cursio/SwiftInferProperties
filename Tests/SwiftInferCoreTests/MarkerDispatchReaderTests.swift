@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// Reading a keyword table from a `String -> E` body, and the names a test can check it with
/// (SwiftInferProperties#644).
@Suite("MarkerDispatchReader")
struct MarkerDispatchReaderTests {

    private func function(_ source: String) -> FunctionDeclSyntax? {
        let finder = Finder(viewMode: .sourceAccurate)
        finder.walk(Parser.parse(source: source))
        return finder.found
    }

    private func read(_ source: String) -> MarkerDispatch? {
        function(source).flatMap(MarkerDispatchReader.read)
    }

    final class Finder: SyntaxVisitor {
        var found: FunctionDeclSyntax?

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            if found == nil { found = node }
            return .visitChildren
        }
    }

    /// The shape of SwiftFormatRuleStudio's `heuristicCategory(for:)`, abridged.
    private static let heuristic = """
    static func heuristicCategory(for ruleName: String) -> FormatRuleCategory {
        let lower = ruleName.lowercased()
        if lower.hasPrefix("redundant") || lower.hasPrefix("unused") {
            return .redundancy
        }
        if lower.contains("comment") || lower.contains("doc")
            || lower.contains("todo") {
            return .comments
        }
        if lower.hasSuffix("wrap") {
            return FormatRuleCategory.wrapping
        }
        return .idiomatic
    }
    """

    @Test func theMotivatingShapeIsReadRowByRowInOrder() throws {
        let dispatch = try #require(read(Self.heuristic))
        #expect(dispatch.isCaseInsensitive)
        #expect(dispatch.rows == [
            MarkerRow(literal: "redundant", test: .hasPrefix, result: ".redundancy"),
            MarkerRow(literal: "unused", test: .hasPrefix, result: ".redundancy"),
            MarkerRow(literal: "comment", test: .contains, result: ".comments"),
            MarkerRow(literal: "doc", test: .contains, result: ".comments"),
            MarkerRow(literal: "todo", test: .contains, result: ".comments"),
            MarkerRow(literal: "wrap", test: .hasSuffix, result: ".wrapping")
        ])
    }

    /// Each marker alone, inside affixes that spell no marker, and upper-cased because the chain
    /// lowercases its input. A prefix marker is affixed only after; a suffix marker only before.
    @Test func probesCheckEachMarkerAloneAffixedAndUpperCased() throws {
        let dispatch = try #require(read(Self.heuristic))
        let names = dispatch.probes().checkable.map(\.name)
        let before = try #require(dispatch.neutralLetters.first).description
        let after = dispatch.neutralLetters[1].description
        #expect(names.contains("doc"))
        #expect(names.contains(before + "doc" + after))
        #expect(names.contains((before + "doc" + after).uppercased()))
        #expect(names.contains("redundant" + after))
        #expect(names.contains(before + "wrap"))
        #expect(names.allSatisfy { dispatch.dispatchedRow(for: $0) != nil })
    }

    /// The affixes contain no letter of any marker, so they cannot complete one across the boundary.
    @Test func neutralLettersAppearInNoMarker() throws {
        let dispatch = try #require(read(Self.heuristic))
        let markerLetters = Set(dispatch.rows.flatMap(\.literal))
        #expect(!dispatch.neutralLetters.isEmpty)
        #expect(dispatch.neutralLetters.allSatisfy { !markerLetters.contains($0) })
    }

    /// **Precedence.** `docs` contains the earlier `doc`, so any name holding it dispatches to the
    /// earlier row: the law would be false as stated, so the marker is reported, not checked.
    @Test func aMarkerAnEarlierRowClaimsIsShadowedNotChecked() throws {
        let dispatch = try #require(read("""
        func kind(of name: String) -> Kind {
            if name.contains("doc") || name.contains("note") { return .prose }
            if name.contains("docs") || name.contains("test") { return .meta }
            return .other
        }
        """))
        let probes = dispatch.probes()
        #expect(probes.shadowed == ["docs"])
        #expect(probes.checkable.contains { $0.name == "test" && $0.result == ".meta" })
        #expect(!probes.checkable.contains { $0.result == ".meta" && $0.name.contains("doc") })
    }

    /// Without a `lowercased()` binding the chain is case-sensitive, and no upper-cased name is emitted.
    @Test func aCaseSensitiveChainEmitsNoUpperCasedNames() throws {
        let dispatch = try #require(read("""
        func kind(of name: String) -> Kind {
            if name.contains("doc") { return .prose }
            if name.contains("test") { return .meta }
            return .other
        }
        """))
        #expect(!dispatch.isCaseInsensitive)
        #expect(dispatch.probes().checkable.allSatisfy { $0.name == $0.name.lowercased() })
    }

    @Test func aLookupFrontingAFallbackIsRead() throws {
        let front = try #require(function("""
        static func category(for ruleName: String) -> FormatRuleCategory {
            curatedCategory(for: ruleName) ?? heuristicCategory(for: ruleName)
        }
        """).flatMap(MarkerDispatchReader.readDelegation))
        #expect(front == FallbackDelegation(
            primaryName: "curatedCategory", primaryLabel: "for", fallbackName: "heuristicCategory"
        ))
    }

    // MARK: - Declined

    @Test("a chain the reader cannot restate is declined", arguments: [
        // A conjunction is not a table row.
        """
        func f(_ s: String) -> K {
            if s.contains("a") && s.contains("b") { return .x }
            if s.contains("c") { return .y }
            return .z
        }
        """,
        // One branch is a predicate, not a table.
        """
        func f(_ s: String) -> K {
            if s.contains("a") { return .x }
            return .z
        }
        """,
        // A marker that is not a literal.
        """
        func f(_ s: String) -> K {
            if s.contains(prefix) { return .x }
            if s.contains("c") { return .y }
            return .z
        }
        """,
        // An uppercase marker against a lowercased input can never match: a dead row, not a law.
        """
        func f(_ s: String) -> K {
            let lower = s.lowercased()
            if lower.contains("Doc") { return .x }
            if lower.contains("c") { return .y }
            return .z
        }
        """,
        // The branch returns something other than a case.
        """
        func f(_ s: String) -> K {
            if s.contains("a") { return make(s) }
            if s.contains("c") { return .y }
            return .z
        }
        """,
        // Not a `String` parameter.
        """
        func f(_ s: Substring) -> K {
            if s.contains("a") { return .x }
            if s.contains("c") { return .y }
            return .z
        }
        """
    ])
    func declinesWhatItCannotRestate(source: String) {
        #expect(read(source) == nil)
    }
}
