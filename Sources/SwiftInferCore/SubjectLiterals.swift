import Foundation
import SwiftParser
import SwiftSyntax

/// The string literals in a subject's own body — the tokens its generator should also draw.
///
/// A parser traps on its own delimiters and an escaper's false laws live in its own entities, and
/// both are literals in its body that no curated token list can know. Handed to the kit's `String`
/// generators as `subjectTokens`, which mix them into the alphanumeric baseline
/// (`RawType.subjectBaseline`, SwiftPropertyLaws v4.8.0).
///
/// ## Measured before it was built
///
/// `docs/plans/subject-literal-generation-scope.md`: drawing these refuted **7 of 52** passing
/// behaviour laws — all false laws a narrow generator hid — and hung **1 of 83** totality laws on a
/// **real defect**, `RuleDocView.parseBlocks` looping forever on its own `"#"` (SwiftProjectLint #257).
/// This is the harvest `scripts/literal_reach_check.py` performed, moved into the tool.
///
/// Only plain literals: an interpolated string has no fixed value to draw, and a literal longer
/// than `maxLength` is prose — an error message, a template — rather than a token the input might
/// contain.
public enum SubjectLiterals {

    /// Most literals kept per subject. The kit caps again; this keeps the stub readable.
    static let cap = 16
    /// Longest literal treated as a token rather than as prose.
    static let maxLength = 40

    /// The literals in the body of the declaration covering `line` of `source`, in source order,
    /// deduplicated; `[]` when no declaration covers the line.
    public static func harvest(declarationAt line: Int, in source: String) -> [String] {
        let tree = Parser.parse(source: source)
        let finder = DeclarationFinder(line: line, converter: SourceLocationConverter(fileName: "", tree: tree))
        finder.walk(tree)
        guard let declaration = finder.innermost else { return [] }
        let collector = LiteralCollector(viewMode: .sourceAccurate)
        collector.walk(declaration)
        var seen: Set<String> = []
        return Array(collector.found.filter { seen.insert($0).inserted }.prefix(cap))
    }

    /// Every literal across a suggestion's evidence — both halves of a round trip — reading each
    /// file once. `[]` for evidence whose file cannot be read, which is every unit-test fixture.
    public static func of(_ suggestion: Suggestion) -> [String] {
        var sources: [String: String] = [:]
        var found: [String] = []
        for evidence in suggestion.evidence where evidence.location.line > 0 {
            let file = evidence.location.file
            if sources[file] == nil {
                sources[file] = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
            }
            found += harvest(declarationAt: evidence.location.line, in: sources[file] ?? "")
        }
        var seen: Set<String> = []
        return Array(found.filter { seen.insert($0).inserted }.prefix(cap))
    }
}

/// Plain string literals, in source order.
private final class LiteralCollector: SyntaxVisitor {
    private(set) var found: [String] = []

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        if let value = node.representedLiteralValue, !value.isEmpty, value.count <= SubjectLiterals.maxLength {
            found.append(value)
        }
        return .skipChildren
    }
}
