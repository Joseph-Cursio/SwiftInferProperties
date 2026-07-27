import Foundation
import PropertyLawKit
@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax

/// Rewriters, corpus and projections for `TriviaInsensitivityExperimentTests`.
/// Split out for `file_length`; the experiment's verdict is documented on the
/// suite itself.
extension TriviaInsensitivityExperimentTests {

    // MARK: - The rewrite

    /// Doubles every existing newline and re-indents, without moving a single
    /// token relative to another.
    ///
    /// Only *existing* newlines are doubled, which makes the rewrite safe by
    /// construction: line structure is preserved and blank lines are added
    /// between things that were already on separate lines. Inserting newlines
    /// where none existed could split an expression; this cannot.
    final class TriviaInflater: SyntaxRewriter {
        override func visit(_ token: TokenSyntax) -> TokenSyntax {
            token
                .with(\.leadingTrivia, Self.inflate(token.leadingTrivia))
                .with(\.trailingTrivia, Self.inflate(token.trailingTrivia))
        }

        /// **Multi-line string literals are not trivia, and this is the finding.**
        ///
        /// Inside `"""…"""` the newlines belong to the string's *value*, so
        /// doubling them adds blank lines to the data. The token-stream guard
        /// caught it on two files; the two scanner laws passed anyway, because
        /// neither looks inside a literal — a passing law over an unsound
        /// rewrite, which is the failure mode this whole file is built to avoid.
        ///
        /// Returning the node without recursing leaves the literal untouched.
        override func visit(_ node: StringLiteralExprSyntax) -> ExprSyntax {
            ExprSyntax(node)
        }

        private static func inflate(_ trivia: Trivia) -> Trivia {
            Trivia(pieces: trivia.flatMap { piece -> [TriviaPiece] in
                switch piece {
                case let .newlines(count):
                    return [.newlines(count * 2)]

                case let .spaces(count):
                    return [.spaces(count + 2)]

                default:
                    return [piece]
                }
            })
        }
    }

    /// Strips every comment, leaving the code identical.
    ///
    /// This is the sharper half of "trivia is not semantics": a doc comment is
    /// prose, and a scanner reporting *structure* must not change its answer
    /// when prose is deleted. A scanner reporting *documentation* must.
    final class CommentStripper: SyntaxRewriter {
        override func visit(_ token: TokenSyntax) -> TokenSyntax {
            token
                .with(\.leadingTrivia, Self.strip(token.leadingTrivia))
                .with(\.trailingTrivia, Self.strip(token.trailingTrivia))
        }

        /// Same carve-out as `TriviaInflater` — see the note there. Stripping a
        /// `//` that happens to sit inside a multi-line literal would delete
        /// characters from a string.
        override func visit(_ node: StringLiteralExprSyntax) -> ExprSyntax {
            ExprSyntax(node)
        }

        private static func strip(_ trivia: Trivia) -> Trivia {
            Trivia(pieces: trivia.filter { piece in
                switch piece {
                case .lineComment, .blockComment, .docLineComment, .docBlockComment:
                    return false

                default:
                    return true
                }
            })
        }
    }

    static func rewritten(_ source: String, by rewriter: SyntaxRewriter) -> String {
        rewriter.rewrite(Parser.parse(source: source)).description
    }

    // MARK: - Corpus
    //
    // Real files from this repo, not synthetic fixtures. A synthetic sample is
    // exactly where a trivia bug would not live — the whole point is code with
    // accumulated formatting habits, alignment, and doc comments.

    static let corpus: [(name: String, source: String)] = {
        // The whole module, not a hand-picked handful. The first version named
        // eight files and yielded 20 summaries — `FunctionScanner` filters
        // non-public declarations, so value-type files contribute almost
        // nothing, and the experiment would have "passed" on a sample too thin
        // to mean anything. The volume check below is what caught that.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 3 { root.deleteLastPathComponent() }
        root.appendPathComponent("Sources/SwiftInferCore")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let swiftFiles = names.filter { $0.hasSuffix(".swift") }.sorted()
        return swiftFiles.compactMap { name in
            (try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8))
                .map { (name, $0) }
        }
    }()

    /// Collapse runs of whitespace. `typeText` and friends preserve the source
    /// *spelling* of a type by design, so `[String: Int]` and `[String:  Int]`
    /// differ as strings while naming the same type. Comparing raw would test
    /// the formatter, not the scanner.
    ///
    /// **This is the experiment's own boundary, and stating it is the result.**
    /// The first version compared raw text and "failed" on 12 files — every one
    /// an interior space inside a type spelling, none a scanner defect. A
    /// metamorphic template would need this normaliser *per output field*, which
    /// is precisely the design cost the experiment was run to discover.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The structural projection of a summary — everything except the docstring.
    /// This is the claim under test: a signature does not depend on formatting.
    static func structure(_ summaries: [FunctionSummary]) -> [String] {
        summaries.map { summary in
            [
                summary.name,
                summary.containingTypeName ?? "-",
                summary.parameters.map { "\($0.label ?? "_"):\($0.typeText)" }.joined(separator: ","),
                summary.returnTypeText ?? "-",
                "\(summary.isStatic)\(summary.isMutating)\(summary.isThrows)\(summary.isAsync)"
            ].joined(separator: "|")
        }
        .map(normalized)
    }

    // MARK: - Failure diagnostics
    //
    // Both fired for real during this experiment and both changed its outcome:
    // the structural diff located the type-spelling whitespace, and the token
    // diff located the multi-line-string-literal unsoundness. Neither was
    // guessable from the failure message alone.

    static func reportStructuralDiff(_ name: String, _ label: String, _ before: [String], _ after: [String]) {
        guard after != before, label == "inflated" else { return }
        for (lhs, rhs) in zip(before, after) where lhs != rhs {
            print("DIFF \(name)\n   before: \(lhs)\n   after:  \(rhs)")
            return
        }
    }

    static func reportTokenDiff(_ name: String, _ label: String, _ before: [String], _ after: [String]) {
        guard after != before else { return }
        let firstDiff = zip(after, before)
            .enumerated()
            .first { $0.element.0 != $0.element.1 }?
            .offset ?? min(after.count, before.count)
        let low = max(0, firstDiff - 4)
        print("TOKDIFF \(name) [\(label)] at \(firstDiff)/\(before.count)")
        print("   before: \(before[low ..< min(before.count, firstDiff + 4)])")
        print("   after:  \(after[low ..< min(after.count, firstDiff + 4)])")
    }
}
