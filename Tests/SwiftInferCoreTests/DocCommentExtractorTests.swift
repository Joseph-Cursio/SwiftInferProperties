import SwiftSyntax
import Testing

@testable import SwiftInferCore

@Suite("DocCommentExtractor — the leading doc comment, reflowed, adjacency-aware")
struct DocCommentExtractorTests {

    @Test("a single-line /// doc is stripped of its marker and one space")
    func singleLine() {
        let trivia = Trivia(pieces: [
            .docLineComment("/// Returns the nearest multiple of 5."),
            .newlines(1)
        ])
        #expect(DocCommentExtractor.docComment(from: trivia) == "Returns the nearest multiple of 5.")
    }

    @Test("multi-line /// doc joins into one reflowed sentence")
    func multiLine() {
        let trivia = Trivia(pieces: [
            .docLineComment("/// Rounds to the nearest multiple of 5,"),
            .newlines(1),
            .docLineComment("/// with ties going upward."),
            .newlines(1)
        ])
        #expect(
            DocCommentExtractor.docComment(from: trivia)
                == "Rounds to the nearest multiple of 5, with ties going upward."
        )
    }

    @Test("a /** */ block doc strips the fence and per-line stars")
    func blockDoc() {
        let trivia = Trivia(pieces: [
            .docBlockComment("/**\n * Orders widgets rank-first.\n * Ties break by name.\n */"),
            .newlines(1)
        ])
        #expect(
            DocCommentExtractor.docComment(from: trivia)
                == "Orders widgets rank-first. Ties break by name."
        )
    }

    @Test("no doc comment yields nil")
    func noDoc() {
        #expect(DocCommentExtractor.docComment(from: Trivia(pieces: [.newlines(1)])) == nil)
        #expect(DocCommentExtractor.docComment(from: []) == nil)
    }

    @Test("an ordinary // line comment is not a doc comment")
    func ordinaryComment() {
        let trivia = Trivia(pieces: [
            .lineComment("// TODO: revisit"),
            .newlines(1)
        ])
        #expect(DocCommentExtractor.docComment(from: trivia) == nil)
    }

    @Test("a doc comment separated by a blank line belongs to a different decl — not captured")
    func blankLineBreaksAdjacency() {
        // `/// old note` then a blank line then the decl: the note documents
        // something above, not this function.
        let trivia = Trivia(pieces: [
            .docLineComment("/// Note about the previous declaration."),
            .newlines(2)
        ])
        #expect(DocCommentExtractor.docComment(from: trivia) == nil)
    }

    @Test("the adjacent doc run is kept even when a stray comment precedes it")
    func adjacentRunWins() {
        // A `// MARK` line, then a blank line, then the real /// doc adjacent to
        // the decl. Only the adjacent /// run is the function's documentation.
        let trivia = Trivia(pieces: [
            .lineComment("// MARK: - Rounding"),
            .newlines(2),
            .docLineComment("/// Returns the nearest multiple."),
            .newlines(1)
        ])
        #expect(DocCommentExtractor.docComment(from: trivia) == "Returns the nearest multiple.")
    }
}
