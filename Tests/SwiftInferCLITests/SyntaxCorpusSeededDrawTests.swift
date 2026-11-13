import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import SwiftInferTemplates
import Testing

/// #684's shipped behaviour, pinned: a stub with seeds admits matching snippets from past the cap and
/// draws biased toward them (lever 1, `seeded`), and drawn arguments of a totality stub are paired
/// (lever 2). Both were measured against the old behaviour behind a switch that no longer exists;
/// `docs/measurements/predicate-reach-at-source.md` has the arms and the decisions.
@Suite("Syntax corpus — seeded draws and paired arguments (#684)")
struct SyntaxCorpusSeededDrawTests {

    private static let base = SyntaxSnippetHarvester.Corpus(
        snippets: ["class B {}"],
        nodeTypeNames: ["Syntax", "ClassDeclSyntax", "DeclSyntax"]
    )
    private static let seeds = SyntaxSeeds(tokens: ["ObservableObject"], kinds: ["AwaitExprSyntax"])

    @Test("by default a stub with seeds admits matching snippets from past the cap and biases the draw")
    func seededIsTheDefault() {
        let source = SyntaxCorpusSource(
            corpus: Self.base,
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

    @Test("the cap and the per-stub admission limit are the measured ones")
    func measuredLimits() {
        #expect(SyntaxCorpusSource.baseLimit == 300)
        #expect(SyntaxCorpusSource.admittedPerStub == 8)
    }

    /// A type only past the cap becomes drawable once a seed admits a snippet holding it.
    @Test("an admitted snippet can make a node type drawable")
    func admittedTypeIsOffered() {
        let source = SyntaxCorpusSource(corpus: Self.base, pastTheCap: ["struct D: ObservableObject {}"])
        #expect(source.generator(for: "StructDeclSyntax") == nil)
        #expect(source.generator(for: "StructDeclSyntax", seeds: Self.seeds) != nil)
    }

    @Test("a stub without seeds keeps the unbiased draw")
    func noSeedsNoBias() {
        let source = SyntaxCorpusSource(corpus: Self.base, pastTheCap: ["class A: ObservableObject {}"])
        #expect(source.generator(for: "ClassDeclSyntax") == "SwiftInferSyntaxCorpus.gen(ClassDeclSyntax.self)")
        #expect(source.snippets == ["class B {}"], "nothing is admitted without seeds")
    }

    @Test("every corpus file carries the reach machinery, and parses")
    func reachFileParses() {
        let text = SyntaxCorpusSource.fileContents(snippets: ["func f() {}"])
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
        let source = SyntaxCorpusSource(corpus: Self.base, pastTheCap: matches)
        _ = source.generator(for: "ClassDeclSyntax", seeds: Self.seeds)
        _ = source.generator(for: "ClassDeclSyntax", seeds: Self.seeds)
        #expect(source.snippets == ["class B {}"] + matches.prefix(SyntaxCorpusSource.admittedPerStub))
    }

    /// Review finding: one `discover` per target writes the same file, so a later writer must keep an
    /// earlier one's admissions.
    @Test("the corpus file reads back, and a merge keeps what is already there")
    func fileReadsBackAndMerges() {
        // A control character is written as an escape since #719, and must read back as itself.
        let snippets = ["func f() {}", "let s = \"\"\"#", "struct S {}", "if a /* \u{07} */ {}"]
        let text = SyntaxCorpusSource.fileContents(snippets: snippets)
        #expect(SyntaxSnippetHarvester.snippets(inCorpusFile: text) == snippets)
        #expect(SyntaxCorpusSource.merged(["a", "x"], adding: ["a", "b", "x", "c"]) == ["a", "x", "b", "c"])
    }

    /// Review finding (#684 cleanup): the merge used to run only under `seeded`, and the dry-run seam
    /// never writes, so nothing caught a guard creeping back.
    @Test("a second writer keeps the first writer's admissions in the shared file")
    func sharedFileKeepsEarlierAdmissions() throws {
        let directory = Self.scratchDirectory("corpus")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(SyntaxCorpusSource.fileName)
        let past = ["class A: ObservableObject {}", "struct E: Equatable {}"]
        let first = SyntaxCorpusSource(corpus: Self.base, pastTheCap: past, destination: file)
        _ = first.generator(for: "ClassDeclSyntax", seeds: Self.seeds)
        let second = SyntaxCorpusSource(corpus: Self.base, pastTheCap: past, destination: file)
        _ = second.generator(for: "StructDeclSyntax", seeds: SyntaxSeeds(tokens: ["Equatable"], kinds: []))
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(SyntaxSnippetHarvester.snippets(inCorpusFile: text) == ["class B {}"] + past)
        #expect(text.contains("preferring tokens: Set<String>"))
    }

    @Test("a seed is escaped into its literal")
    func arrayLiteral() {
        #expect(SyntaxCorpusSource.arrayLiteral(["a\"b", "c\\d"]) == #"["a\"b", "c\\d"]"#)
        #expect(SyntaxCorpusSource.arrayLiteral([]) == "[]")
    }

    private static func scratchDirectory(_ label: String) -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(label)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - The production path: a suggestion's own seeds reach the draw

    private static let rulesSource = """
    import SwiftSyntax
    func observes(_ node: ClassDeclSyntax) -> Bool {
        node.description.contains("ObservableObject")
    }
    """

    private static func resolved(template: String, file: URL, corpus: SyntaxCorpusSource?) -> String? {
        var context = InteractiveTriage.Context(
            prompt: TriageRecordingPromptInput(scriptedLines: []),
            output: TriageRecordingOutput(),
            diagnostics: TriageRecordingDiagnosticOutput(),
            outputDirectory: file.deletingLastPathComponent(),
            dryRun: true
        )
        context.syntaxCorpus = corpus
        let subject = Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: "observes(_:)",
                    signature: "(ClassDeclSyntax) -> Bool",
                    location: SourceLocation(file: file.path, line: 2, column: 1)
                ),
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "Rules.swift::observes(_:)")
        )
        return InteractiveTriage.recordingGenerator(for: context, suggestion: subject).0("ClassDeclSyntax")
    }

    /// Review finding (#684 cleanup): every test above passes seeds by hand, so the wiring discover uses —
    /// `recordingGenerator` → `SeedReading` → `generator(for:seeds:)` — could fall back to the unbiased draw
    /// with the suite green.
    @Test("a predicate's seeds, read from its source, bias the generator discover resolves")
    func suggestionSeedsReachTheDraw() throws {
        let directory = Self.scratchDirectory("seeds")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Rules.swift")
        try Self.rulesSource.write(to: file, atomically: true, encoding: .utf8)
        let corpus = SyntaxCorpusSource(corpus: Self.base)

        let predicate = Self.resolved(template: "predicate", file: file, corpus: corpus)
        #expect(predicate?.contains(#"preferring: ["ObservableObject"]"#) == true)
        let unseeded = Self.resolved(template: "idempotence", file: file, corpus: corpus)
        #expect(unseeded == "SwiftInferSyntaxCorpus.gen(ClassDeclSyntax.self)", "control: a template reading no seeds")
        let uncorpused = Self.resolved(template: "predicate", file: file, corpus: nil) ?? ""
        #expect(!uncorpused.contains("SwiftInferSyntaxCorpus"), "control: no corpus, no corpus draw")
    }

    // MARK: - Lever 2, shipped

    private static func predicate(_ displayName: String, signature: String) -> Suggestion {
        Suggestion(
            templateName: "predicate",
            evidence: [
                Evidence(
                    displayName: displayName,
                    signature: signature,
                    location: SourceLocation(file: "F.swift", line: 1, column: 1),
                    qualifiedTypeName: "Rules"
                ),
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "F.swift::\(displayName)")
        )
    }

    @Test("a totality stub pairs its drawn arguments by default")
    func pairingIsTheDefault() throws {
        let stub = try #require(InteractiveTriage.entailedTemplateStub(
            for: Self.predicate("isListed(_:in:)", signature: "(String, [String]) -> Bool")
        ))
        #expect(stub.contains("if Bool.random(using: &rng) { arg1.append(arg0) }"))
        #expect(stub.contains("var arg1 = "), "a paired argument is drawn into a var")
    }

    @Test("control: a stub with nothing to pair draws exactly as before")
    func nothingToPair() throws {
        let stub = try #require(InteractiveTriage.entailedTemplateStub(
            for: Self.predicate("isPositive(_:)", signature: "(Int) -> Bool")
        ))
        #expect(!stub.contains("Bool.random(using: &rng)"))
        #expect(!stub.contains("Int.random(in: 0 ..< 4, using: &rng)"))
    }
}
