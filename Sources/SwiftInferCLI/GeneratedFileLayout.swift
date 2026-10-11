import SwiftParser
import SwiftSyntax

/// Lays a generated test file out within SwiftLint's default limits, so the file `discover
/// --interactive` writes into someone's test target does not add to their lint debt.
///
/// ## Why one pass over the finished file, and not a change in each emitter
///
/// Line length is decided by text no emitter controls: the subject's own names, and generator
/// expressions the kit renders (`MemberwiseEmitter`'s `zip(…)\n.map { T(…) }`, `RawType`'s
/// literal lists). Measured on SwiftLintRuleStudio's core package, 59 accepted stubs carried 194
/// `line_length` and 35 `closure_end_indentation` violations, the longest line 632 characters,
/// and every one of them came from a spliced expression rather than from an emitter's template.
/// A dozen emitters each wrapping its own output would leave the next one to get it wrong; the
/// accept path is the one place every stub passes through — the same reasoning as
/// `namespaced(_:suiteName:)`.
///
/// ## What it changes, and why that cannot change what the file means
///
/// Only a *region* with a defect is touched: a line over the limit, a line continuing a chain
/// (`.map …` at the head of a line), or a bracket closed out of line with where it opened. A
/// region is the smallest run of lines whose brackets balance, so it is a statement or an
/// argument; it is flattened to one line and broken again by `LayoutBreaker`, which inserts line
/// breaks only after an opener, a comma or a `;`, before a closer, and before a chain's `.`. None
/// of those positions is one where Swift reads a newline as meaning anything.
///
/// Three rewrites change tokens, each forced by a rule and each value-preserving — a closure's
/// `$0` named when the closure must span lines (`shorthand_argument`), a long string literal
/// continued over lines with `\` (`line_length`), and `.map { $0! }` drawn as
/// `.compactMap(\.self)` (`force_unwrapping`). One moves code: a generator too long for its line
/// becomes a static on the suite (`GeneratedFileGeneratorHoist`), since wrapped in place it would
/// take the test past `function_body_length`. And every region is re-checked with SwiftParser after
/// it is replaced: one that would introduce a syntax error is put back as it was.
///
/// ## What it cannot do
///
/// A line with no bracket to break at, a comment-only line with no space to wrap at, and a region
/// holding a `//` comment are left as they are; so is a whole file that does not parse, or whose
/// brackets do not balance.
enum GeneratedFileLayout {

    static let lineLimit = 120
    static let indentWidth = 4

    static func laidOut(_ contents: String) -> String {
        var lines = contents.components(separatedBy: "\n")
        lines = lines.map(Self.rewritingForceUnwraps)
        if parses(lines) {
            let hoisted = GeneratedFileGeneratorHoist.hoisted(lines)
            if parses(hoisted) { lines = hoisted }
        }
        lines = relaidRegions(lines)
        lines = GeneratedFileText.wrappingLongComments(lines)
        lines = GeneratedFileText.wrappingLongLiteralContent(lines)
        lines = GeneratedFileText.collapsingBlankLines(lines)
        return lines.joined(separator: "\n")
    }

    /// `.map { $0! }` → `.compactMap(\.self)`.
    ///
    /// The kit renders the first for every literal-list string generator
    /// (`Gen<String?>.element(of: [...] as [String]).map { $0! }`), and so do four writers here.
    /// The two draw the same value from the same random state — `compactMap` and `map` share one
    /// `run` and one shrinker, and the element is never `nil` for a non-empty list — so the only
    /// difference is an empty list, where the force unwrap traps and `compactMap` filters.
    /// `\.self` rather than `{ $0 }`, which `prefer_key_path` flags.
    static func rewritingForceUnwraps(_ line: String) -> String {
        line.replacingOccurrences(of: ".map { $0! }", with: ".compactMap(\\.self)")
    }

    /// Every defective region, re-laid out, outermost first so a region is never broken twice.
    static func relaidRegions(_ lines: [String]) -> [String] {
        let scan = GeneratedFileScan(lines)
        guard scan.balanced, Self.parses(lines) else { return lines }
        let regions = GeneratedFileRegions(lines: lines, scan: scan).defective
        var result = lines
        // Bottom-up, so replacing one region does not move the line numbers of the next.
        for region in regions.reversed() {
            let original = Array(result[region])
            guard let replacement = relaid(original, indent: GeneratedFileScan.indent(of: original[0])),
                  replacement != original else { continue }
            var candidate = result
            candidate.replaceSubrange(region, with: replacement)
            if parses(candidate) { result = candidate }
        }
        return result
    }

    /// One region, flattened and broken again; `nil` when it cannot be read.
    static func relaid(_ region: [String], indent: Int) -> [String]? {
        guard let flat = GeneratedFileRegions.flattened(region),
              let nodes = LayoutParser.nodes(flat) else { return nil }
        return LayoutBreaker(limit: lineLimit, indentWidth: indentWidth).lines(for: nodes.trimmed, indent: indent)
    }

    /// Whether `lines` parse as Swift with no syntax error.
    static func parses(_ lines: [String]) -> Bool {
        let tree = Parser.parse(source: lines.joined(separator: "\n"))
        return !tree.hasError
    }
}
