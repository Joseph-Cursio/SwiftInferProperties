import Foundation
import SwiftSyntax

/// Pulls a declaration's leading documentation comment out of its trivia and
/// reflows it to plain prose, for `FunctionSummary.docComment`.
///
/// The docstring advisory downstream reads that prose as a candidate
/// **reference definition** — the sentence a `predicate` law owes, the spec a
/// lifted example test needs, or the only contract on a function the templates
/// could offer nothing refutable for. This type does *not* judge whether the
/// prose is a contract or mere narration; that classification lives next to
/// `Refutability`. Here we only find the comment and clean it up.
///
/// **Only the doc-comment run adjacent to the declaration counts.** A comment
/// separated from the `func` by a blank line is a section divider or a note
/// about the *previous* declaration, not this one's documentation — Swift's own
/// doc tooling draws the same line, and so do we (stop at any blank line).
public enum DocCommentExtractor {

    /// The declaration's doc comment as reflowed prose, or `nil` when it carries
    /// none. `///` markers and `/** */` fences are stripped, a single leading
    /// space per line removed, and the surviving lines joined with single
    /// spaces so keyword scanning and one-line presentation both work.
    public static func docComment(from trivia: Trivia) -> String? {
        let lines = docLines(from: trivia)
        guard !lines.isEmpty else { return nil }
        let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? nil : joined
    }

    /// The cleaned individual doc lines adjacent to the declaration, in source
    /// order. Empty when there is no adjacent doc-comment run.
    private static func docLines(from trivia: Trivia) -> [String] {
        // Walk the pieces from the end (nearest the declaration) backward,
        // collecting doc-comment lines. Whitespace and single newlines between
        // doc pieces are part of the same run; a blank line (two or more
        // newlines) or any non-doc token ends it — everything before that
        // belongs to a different declaration or is a section break.
        var collected: [String] = []
        for piece in trivia.pieces.reversed() {
            switch piece {
            case let .docLineComment(text):
                collected.append(stripLine(text))

            case let .docBlockComment(text):
                // We are walking pieces in reverse and reverse `collected` at the
                // end; a block's own lines are already in source order, so append
                // them reversed to survive that final flip.
                collected.append(contentsOf: stripBlock(text).reversed())

            case .spaces, .tabs, .carriageReturns:
                continue

            case let .newlines(count), let .carriageReturnLineFeeds(count):
                if count >= 2 { return collected.reversed() }
                continue

            default:
                // A line comment, an attribute's trivia, or any other content
                // breaks the adjacency: stop and keep what we have.
                return collected.reversed()
            }
        }
        return collected.reversed()
    }

    /// Strip `///` (or a legacy `//`) and one optional following space.
    private static func stripLine(_ raw: String) -> String {
        var text = Substring(raw)
        if text.hasPrefix("///") {
            text = text.dropFirst(3)
        } else if text.hasPrefix("//") {
            text = text.dropFirst(2)
        }
        if text.first == " " { text = text.dropFirst() }
        return String(text)
    }

    /// Strip a `/** … */` fence and per-line leading `*` decoration, returning
    /// the non-empty content lines.
    private static func stripBlock(_ raw: String) -> [String] {
        var body = Substring(raw)
        if body.hasPrefix("/**") { body = body.dropFirst(3) }
        if body.hasSuffix("*/") { body = body.dropLast(2) }
        return body.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            var trimmed = line.drop { $0 == " " || $0 == "\t" }
            if trimmed.first == "*" {
                trimmed = trimmed.dropFirst()
                if trimmed.first == " " { trimmed = trimmed.dropFirst() }
            }
            let cleaned = String(trimmed).trimmingCharacters(in: .whitespaces)
            return cleaned.isEmpty ? nil : cleaned
        }
    }
}
