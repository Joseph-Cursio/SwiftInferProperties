import Foundation
import PropertyLawKit
@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// **Experiment: is a metamorphic law family worth building?**
///
/// The catalogue names value-semantic shapes — `(T) -> T`, `(T, T) -> T`,
/// round-trip pairs. A scanner is `SourceFileSyntax -> [Finding]`, which matches
/// none of them, and the self-dogfood road test measured the consequence
/// exactly: **715 seeds in `SwiftInferCLI` produced two default-tier picks**
/// (`docs/roadtest-self-dogfood.md` §3). The engine is out of catalog on its own
/// analysis layer.
///
/// The family that fits parser-adjacent code is *metamorphic*: not "f(x) equals
/// this value" but "f(x) and f(W(x)) are related, for a semantics-preserving
/// rewrite W". The cheapest such W is **trivia** — whitespace and comments —
/// because it is *definitionally* not semantics, so no judgement about Swift is
/// required to know the rewrite is safe.
///
/// This file is the experiment before the machinery, deliberately hand-written
/// for three scanners rather than generalised into a template kind. If a scanner
/// fails, the direction is proven for an afternoon's work. If all pass, that is
/// learned far more cheaply than by building the template first — and the risk
/// being tested for is real, because a metamorphic catalogue that produces
/// hundreds of always-passing picks is the Daikon trap in a new costume, which
/// `CLAUDE.md` says to avoid by raising thresholds rather than adding filters.
///
/// **VERDICT — measured, 120 files / 322 summaries / 232 shapes / 10 visitors.**
///
/// All three scanners are trivia-insensitive. No defect was found, and that is
/// the smaller half of the result. The larger half is what the experiment cost
/// to *state*, because every obstacle below is a cost a template kind would
/// have to pay on every carrier, and none of the three can be inferred:
///
///  1. **Type text is a source spelling.** `[String: Int]` and `[String:  Int]`
///     name one type and differ as strings, so the comparison needs whitespace
///     normalisation. Without it the law "fails" on 12 files, every one a space
///     inside a type spelling and not one a scanner defect.
///  2. **Locations are coordinates into the text.** `RuleVisitorCandidate`
///     carries `"File.swift:214"`, and reformatting moves line 214 — so it is
///     trivia-*sensitive* by construction. Positional fields must be projected
///     away per output type. A template cannot tell a coordinate from a fact.
///  3. **Trivia is not non-semantic in Swift.** Inside `"""…"""` the newlines
///     are the string's *value*. The rewrite itself needs a carve-out, or it
///     silently changes what the program means — see `TriviaInflater`.
///
/// And the two controls below (`docComment`, `SkipMarkerScanner`) are
/// trivia-sensitive **on purpose**, so a blanket "scanner output is invariant
/// under trivia rewriting" entry would be flatly wrong for them.
///
/// So the honest catalogue entry is not "scanner output is trivia-insensitive"
/// but "*trivia-insensitive modulo a per-output-type projection*" — and the
/// projection is hand-written curation, three of them for three scanners here.
/// That is real, and it is not free. It is the same shape as the road test's
/// central finding: a derived generator is tuned for coverage of the **type**
/// and silently mistuned for coverage of the **law**
/// (`docs/roadtest-self-dogfood.md` §12).
///
/// **Subjects, chosen so the result discriminates:**
///
/// | Subject | Expectation | Why |
/// |---|---|---|
/// | `FunctionScanner.scan`, structural fields | invariant | a signature does not depend on blank lines |
/// | `TypeShapeBuilder.shapes` | invariant | a type's shape carries no trivia at all |
/// | `RuleVisitorDiscoverer` (sans location) | invariant | reads bodies — the most exposed of the three |
/// | `FunctionSummary.docComment` | **variant** | it reads comments; it *must* change |
/// | `SkipMarkerScanner` | **split** | reformat: invariant. strip comments: empty. |
///
/// **POPULATION, measured 2026-08-01 — and it does not change the verdict.**
///
/// The experiment above tested three scanners in one repo, so the obvious
/// objection was that the family might simply be too rare to matter. It is not.
/// Carriers of the shape `(syntax-ish) -> collection`, plus `SyntaxVisitor` /
/// `SyntaxRewriter` subclasses:
///
/// | repo | syntax→collection | visitor subclasses |
/// |---|---:|---:|
/// | SwiftLint | 21 | **317** |
/// | swift-syntax | 120 | 28 |
/// | this repo | 35 | 23 |
/// | SwiftProjectLint | 12 | 35 |
/// | swift-format | 1 | 7 |
///
/// ~599 in total, an upper bound — the shape filter is crude and caught obvious
/// non-collectors (`NSRegularExpression.matches`). Even discounted heavily it is
/// two orders of magnitude above the shapes the swift.org study *declined* for
/// want of population (27 product-typed returns; 106 parser residues across nine
/// corpora — findings §7.1).
///
/// **So population was never the blocker, and that is the point worth carrying.**
/// The three obstacles above are about whether the law can be *stated*, not
/// whether there is anything to state it about. A coordinate and a fact look
/// identical from outside the type. That is a *statability* gap, and it is a
/// different failure mode from the four the study's taxonomy names (not scanned /
/// not paired / not templated / suppressed) — here the shape is templatable in
/// principle and the per-carrier projection is not inferable in practice.
///
/// Confirmed independently on the same day: `SwiftProjectLintVisitors` is **114
/// functions, 114 of them inferred pure** — the tool's hardest gate fully
/// satisfied on every one — and yields 21 suggestions of which 15 are
/// `predicate`. Purity is not what is stopping this.
///
/// The last two are controls. A rewrite that leaves docstrings alone is not
/// rewriting trivia, and the passes above would be vacuous — the same
/// degenerate-green that made the first collision sweep report a clean pass
/// while reaching nothing. The volume check exists for the same reason: the
/// first corpus here was eight hand-picked files yielding 20 summaries, because
/// `FunctionScanner` filters non-public declarations.
///
@Suite("Experiment — trivia-insensitivity as a metamorphic law")
struct TriviaInsensitivityExperimentTests {

    // MARK: - Subject 1 — FunctionScanner structural output

    /// Volume check — a pass over an empty corpus, or over files yielding no
    /// summaries, would be vacuous. Four times today a green result carried no
    /// information until the mechanism was watched producing a red one.
    @Test("the experiment is not vacuous")
    func experimentIsNotVacuous() {
        var files = 0, summaries = 0, shapes = 0, docs = 0, visitors = 0
        for (name, source) in Self.corpus {
            files += 1
            let corpus = FunctionScanner.scanCorpus(source: source, file: name)
            summaries += corpus.summaries.count
            docs += corpus.summaries.compactMap(\.docComment).count
            shapes += TypeShapeBuilder.shapes(from: corpus.typeDecls).count
            visitors += RuleVisitorDiscoverer.discover(source: source, file: name).count
        }
        print("VOLUME files=\(files) summaries=\(summaries) shapes=\(shapes) docComments=\(docs) visitors=\(visitors)")
        #expect(files > 60, "corpus too small: \(files)")
        #expect(summaries > 300, "too few functions scanned: \(summaries)")
        #expect(shapes > 100, "too few type shapes: \(shapes)")
        #expect(docs > 200, "too few doc comments — the control would be weak: \(docs)")
        #expect(visitors > 3, "too few rule visitors: \(visitors)")
    }

    @Test("FunctionScanner's structural output is invariant under trivia rewriting")
    func functionScannerIsTriviaInsensitive() {
        #expect(!Self.corpus.isEmpty, "corpus did not load — the experiment would be vacuous")
        for (name, source) in Self.corpus {
            let original = Self.structure(FunctionScanner.scan(source: source, file: name))
            for (label, rewriter) in [
                ("inflated", TriviaInflater() as SyntaxRewriter),
                ("comments-stripped", CommentStripper())
            ] {
                let rewrittenSource = Self.rewritten(source, by: rewriter)
                let after = Self.structure(FunctionScanner.scan(source: rewrittenSource, file: name))
                Self.reportStructuralDiff(name, label, original, after)
                #expect(after == original, "\(name) changed under \(label)")
            }
        }
    }

    /// Whitespace-normalised projection of a type shape. Generic over the shape
    /// type and built from `String(describing:)` deliberately — that covers
    /// *every* field, including any added later, so the law cannot silently
    /// narrow the way a hand-listed projection would.
    private static func shapeProjection<T>(_ shapes: [T]) -> [String] {
        shapes.map { normalized(String(describing: $0)) }
    }

    // MARK: - Subject 2 — TypeShapeBuilder

    @Test("TypeShapeBuilder's shapes are invariant under trivia rewriting")
    func typeShapeBuilderIsTriviaInsensitive() {
        for (name, source) in Self.corpus {
            let original = Self.shapeProjection(TypeShapeBuilder.shapes(
                from: FunctionScanner.scanCorpus(source: source, file: name).typeDecls
            ))
            for (label, rewriter) in [
                ("inflated", TriviaInflater() as SyntaxRewriter),
                ("comments-stripped", CommentStripper())
            ] {
                let rewrittenSource = Self.rewritten(source, by: rewriter)
                let after = Self.shapeProjection(TypeShapeBuilder.shapes(
                    from: FunctionScanner.scanCorpus(source: rewrittenSource, file: name).typeDecls
                ))
                #expect(after == original, "\(name) changed under \(label)")
            }
        }
    }

    // MARK: - Subject 3 — RuleVisitorDiscoverer

    /// **`location` is projected away, and that is a result, not a convenience.**
    ///
    /// A `RuleVisitorCandidate` carries `"File.swift:214"`. Reformatting moves
    /// line 214, so the raw candidate is trivia-*sensitive* by construction and
    /// the whole-description projection that worked for `TypeShape` reports a
    /// difference on every file. Positional data has to be excluded per output
    /// type, by hand — a template kind cannot infer which fields are
    /// coordinates into the text and which are facts about the code.
    private static func visitorProjection(_ candidates: [RuleVisitorCandidate]) -> [String] {
        candidates.map { candidate in
            normalized([
                candidate.typeName,
                candidate.inheritedTypes.joined(separator: ","),
                candidate.visitedNodeTypes.joined(separator: ","),
                candidate.emittedRuleNames.joined(separator: ",")
            ].joined(separator: "|"))
        }
    }

    /// The third scanner, and structurally the most exposed of the three: it
    /// reads *inside function bodies* (the `ruleName:` arguments a visitor
    /// emits) rather than stopping at declarations. If trivia sensitivity lives
    /// anywhere in this layer, a body-reading scanner is where to look.
    @Test("RuleVisitorDiscoverer is invariant under trivia rewriting")
    func ruleVisitorDiscovererIsTriviaInsensitive() {
        for (name, source) in Self.corpus {
            let original = Self.visitorProjection(RuleVisitorDiscoverer.discover(source: source, file: name))
            for (label, rewriter) in [
                ("inflated", TriviaInflater() as SyntaxRewriter),
                ("comments-stripped", CommentStripper())
            ] {
                let after = Self.visitorProjection(
                    RuleVisitorDiscoverer.discover(source: Self.rewritten(source, by: rewriter), file: name)
                )
                #expect(after == original, "\(name) changed under \(label)")
            }
        }
    }

    // MARK: - Subject 4 — a scanner that reads comments *on purpose*
    //
    // `SkipMarkerScanner` looks for `// swift-infer:skip <hash>`. It is the one
    // place in this layer where a comment is an instruction rather than prose,
    // and it splits the two rewrites cleanly: reformatting must not move a
    // marker, deleting comments must remove every one of them. A single
    // "trivia-insensitive" template kind would get this scanner wrong in one
    // direction or the other, which is an argument about the *shape* of the
    // catalogue entry, not about this scanner.

    /// Real files with a marker injected — SwiftInferCore ships none of its own,
    /// and asserting over an empty marker set is the vacuous pass again.
    private static let markedCorpus: [(name: String, source: String)] = corpus.prefix(30).map {
        ($0.name, "// swiftinfer: skip 0xABCDEF01\n" + $0.source)
    }

    @Test("SkipMarkerScanner finds the same markers after reformatting")
    func skipMarkersSurviveReformatting() {
        var found = 0
        for (name, source) in Self.markedCorpus {
            let original = SkipMarkerScanner.skipHashes(in: source)
            found += original.count
            let after = SkipMarkerScanner.skipHashes(in: Self.rewritten(source, by: TriviaInflater()))
            #expect(after == original, "\(name): reformatting moved a skip marker")
        }
        #expect(found == Self.markedCorpus.count, "markers were not injected: \(found)")
    }

    /// The mirror, and it must FAIL to be worth anything: deleting comments has
    /// to delete the markers.
    @Test("the control: stripping comments removes every skip marker")
    func skipMarkersDieWithComments() {
        for (name, source) in Self.markedCorpus {
            let after = SkipMarkerScanner.skipHashes(in: Self.rewritten(source, by: CommentStripper()))
            #expect(after.isEmpty, "\(name): a marker survived comment stripping")
        }
    }

    // MARK: - Subject 5 — the control

    /// **The control, and it must FAIL to be worth anything.**
    ///
    /// `docComment` reads comments, so stripping them has to change the answer.
    /// If this reported "invariant", the rewrite would not be rewriting and the
    /// two passes above would be vacuous — the degenerate-green shape that made
    /// the first collision sweep pass cleanly while reaching nothing
    /// (`docs/roadtest-self-dogfood.md` §13.3).
    @Test("the control: docComment IS trivia-sensitive, proving the rewrite bites")
    func docCommentIsTriviaSensitive() {
        var sawADifference = false
        for (name, source) in Self.corpus {
            let original = FunctionScanner.scan(source: source, file: name).compactMap(\.docComment)
            let stripped = Self.rewritten(source, by: CommentStripper())
            let after = FunctionScanner.scan(source: stripped, file: name).compactMap(\.docComment)
            if !original.isEmpty, after.count < original.count { sawADifference = true }
        }
        #expect(
            sawADifference,
            """
            Stripping comments changed no docstring anywhere in the corpus. \
            The rewriter is not rewriting, which makes every other assertion in \
            this file vacuous.
            """
        )
    }

    /// The rewrites must also **preserve the code** — an inflater that dropped a
    /// token would make the scanners agree for the wrong reason.
    @Test("the rewrites change only trivia, never the token stream")
    func rewritesPreserveTheTokenStream() {
        for (name, source) in Self.corpus {
            let parsed = Parser.parse(source: source)
            let originalTokens = parsed.tokens(viewMode: .sourceAccurate).map(\.text)
            for (label, rewriter) in [
                ("inflated", TriviaInflater() as SyntaxRewriter),
                ("comments-stripped", CommentStripper())
            ] {
                let reparsed = Parser.parse(source: Self.rewritten(source, by: rewriter))
                let after = reparsed.tokens(viewMode: .sourceAccurate).map(\.text)
                Self.reportTokenDiff(name, label, originalTokens, after)
                #expect(after == originalTokens, "\(name): \(label) altered the token stream")
            }
        }
    }
}
