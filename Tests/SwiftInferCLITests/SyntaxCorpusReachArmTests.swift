@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// #684's arms: which snippets a stub draws from, and how (`docs/plans/predicate-reach-at-source-scope.md`).
@Suite("Syntax corpus — the #684 reach arms")
struct SyntaxCorpusReachArmTests {

    private static let base = SyntaxSnippetHarvester.Corpus(
        snippets: ["class B {}"],
        nodeTypeNames: ["Syntax", "ClassDeclSyntax", "DeclSyntax"]
    )
    private static let seeds = SyntaxSeeds(tokens: ["ObservableObject"], kinds: ["AwaitExprSyntax"])

    @Test("the baseline arm ignores seeds and writes the file it always wrote")
    func baselineUnchanged() {
        let source = SyntaxCorpusSource(corpus: Self.base, pastTheCap: ["class A: ObservableObject {}"])
        #expect(source.generator(for: "ClassDeclSyntax", seeds: Self.seeds)
            == "SwiftInferSyntaxCorpus.gen(ClassDeclSyntax.self)")
        #expect(source.snippets == ["class B {}"])
        let plain = SyntaxCorpusSource.fileContents(snippets: ["x"])
        #expect(plain == SyntaxCorpusSource.fileContents(snippets: ["x"], reach: false))
    }

    @Test("the seeded arm admits matching snippets from past the cap and biases the draw")
    func seededAdmits() {
        let source = SyntaxCorpusSource(
            corpus: Self.base,
            arm: ReachArm(corpus: .seeded, paired: false),
            pastTheCap: ["class A: ObservableObject {}", "class C {}", "struct D: ObservableObject {}"]
        )
        #expect(source.generator(for: "ClassDeclSyntax", seeds: Self.seeds)
            == "SwiftInferSyntaxCorpus.gen(ClassDeclSyntax.self, "
            + #"preferring: ["ObservableObject"], kinds: ["AwaitExprSyntax"])"#)
        #expect(source.snippets == ["class B {}", "class A: ObservableObject {}"])
        // A second stub asking the same admits nothing twice.
        _ = source.generator(for: "ClassDeclSyntax", seeds: Self.seeds)
        #expect(source.snippets.count == 2)
    }

    /// A type only past the cap becomes drawable once a seed admits a snippet holding it.
    @Test("an admitted snippet can make a node type drawable")
    func admittedTypeIsOffered() {
        let source = SyntaxCorpusSource(
            corpus: Self.base,
            arm: ReachArm(corpus: .seeded, paired: false),
            pastTheCap: ["struct D: ObservableObject {}"]
        )
        #expect(source.generator(for: "StructDeclSyntax") == nil)
        #expect(source.generator(for: "StructDeclSyntax", seeds: Self.seeds) != nil)
    }

    @Test("a stub without seeds keeps the unbiased draw under every arm")
    func noSeedsNoBias() {
        let source = SyntaxCorpusSource(corpus: Self.base, arm: ReachArm(corpus: .uncapped, paired: true))
        #expect(source.generator(for: "ClassDeclSyntax") == "SwiftInferSyntaxCorpus.gen(ClassDeclSyntax.self)")
    }

    @Test("the file with the reach machinery parses")
    func reachFileParses() {
        let text = SyntaxCorpusSource.fileContents(snippets: ["func f() {}"], reach: true)
        #expect(SyntaxSnippetHarvester.parsesCleanly(text))
        #expect(text.contains("preferring tokens: Set<String>"))
        // A hoisted `static let` cannot infer an opaque type from another declaration (smoke run, §9 A3).
        #expect(text.contains(") -> Generator<Node, Shrink.None<Node>> {"))
        #expect(text.contains("static func name<Node: SyntaxProtocol, R: RandomNumberGenerator>("))
    }

    /// Review finding: a second ask admitted the NEXT eight, so the file depended on how often stubs asked.
    @Test("admission takes the first matches in file order, and asking again admits nothing")
    func admissionIsIdempotent() {
        let matches = (0 ..< 12).map { "class M\($0): ObservableObject {}" }
        let source = SyntaxCorpusSource(
            corpus: Self.base, arm: ReachArm(corpus: .seeded, paired: false), pastTheCap: matches
        )
        _ = source.generator(for: "ClassDeclSyntax", seeds: Self.seeds)
        _ = source.generator(for: "ClassDeclSyntax", seeds: Self.seeds)
        #expect(source.snippets == ["class B {}"] + matches.prefix(SyntaxCorpusSource.admittedPerStub))
    }

    /// Review finding: one `discover` per target writes the same file, so a later writer must keep an
    /// earlier one's admissions.
    @Test("the corpus file reads back, and a merge keeps what is already there")
    func fileReadsBackAndMerges() {
        let snippets = ["func f() {}", "let s = \"\"\"#", "struct S {}"]
        let text = SyntaxCorpusSource.fileContents(snippets: snippets, reach: true)
        #expect(SyntaxSnippetHarvester.snippets(inCorpusFile: text) == snippets)
        #expect(SyntaxCorpusSource.merged(["a", "x"], adding: ["a", "b", "x", "c"]) == ["a", "x", "b", "c"])
    }

    @Test("a seed is escaped into its literal")
    func arrayLiteral() {
        #expect(SyntaxCorpusSource.arrayLiteral(["a\"b", "c\\d"]) == #"["a\"b", "c\\d"]"#)
        #expect(SyntaxCorpusSource.arrayLiteral([]) == "[]")
    }

    @Test("arm spellings", arguments: [
        (nil, ReachArm.baseline), ("", .baseline), ("baseline", .baseline),
        ("seeded", ReachArm(corpus: .seeded, paired: false)),
        ("uncapped+paired", ReachArm(corpus: .uncapped, paired: true)),
        ("baseline+paired", ReachArm(corpus: .baseline, paired: true)),
    ] as [(String?, ReachArm)])
    func armSpellings(raw: String?, expected: ReachArm) {
        #expect(ReachArm.parse(raw) == expected)
    }

    @Test("an unknown spelling names no arm", arguments: ["seed", "seeded+pair", "seeded+paired+x", "+paired"])
    func unknownArm(raw: String) {
        #expect(ReachArm.parse(raw) == nil)
    }
}
