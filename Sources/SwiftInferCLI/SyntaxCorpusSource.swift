import Foundation
import SwiftInferCore

/// Generators for SwiftSyntax node parameters, drawn from snippets the package's own tests parse.
///
/// One per `discover --interactive` run. Nothing is harvested until a stub asks for a node type,
/// and the corpus file is written beside the stubs the first time one uses it — a run over code
/// that takes no syntax nodes touches nothing. See `SyntaxSnippetHarvester` for what a snippet is
/// and why the tests are the source.
///
/// The emitted file declares one type, `SwiftInferSyntaxCorpus`, whose `gen(_:)` parses every
/// snippet, collects the nodes of the requested type and draws among them. It imports
/// `SwiftParser`, which a package analysing Swift already builds; a test target reaching it only
/// transitively still compiles under SwiftPM, measured on SwiftProjectLintVisitors.
final class SyntaxCorpusSource {

    static let typeName = "SwiftInferSyntaxCorpus"
    static let fileName = "\(typeName).swift"

    /// Snippets kept before any seed admits more — the cap `07803176` set "so the emitted file stays
    /// reviewable", never measured. #684 measures what it costs (`ReachArm`).
    static let baseLimit = 300
    /// Most snippets one stub's seeds admit past `baseLimit` (`ReachArm.Corpus.seeded`).
    static let admittedPerStub = 8

    private let testRoots: [URL]
    private let destination: URL
    private let dryRun: Bool
    let arm: ReachArm
    private lazy var corpus: SyntaxSnippetHarvester.Corpus = {
        switch arm.corpus {
        case .baseline, .seeded:
            return SyntaxSnippetHarvester.harvest(roots: testRoots, limit: Self.baseLimit)

        case .uncapped:
            return SyntaxSnippetHarvester.harvest(roots: testRoots, limit: .max)
        }
    }()
    /// Every candidate past `baseLimit`, indexed for seeded admission. Built on the first seeded ask.
    private lazy var pastTheCap = SnippetIndex(snippets: Array(
        SyntaxSnippetHarvester.harvest(roots: testRoots, limit: .max).snippets.dropFirst(Self.baseLimit)
    ))
    private var admitted: [SnippetIndex.Entry] = []
    private var admittedTypeNames: Set<String> = []
    private var lastWritten: [String]?

    /// - Parameters:
    ///   - packageRoot: the package whose tests are harvested — every top-level directory named
    ///     `Tests` or ending in `Tests`.
    ///   - generatedRoot: the directory holding `SwiftInfer/`; the corpus file goes inside it.
    init(packageRoot: URL, generatedRoot: URL, dryRun: Bool, arm: ReachArm = .current) {
        // ⚠ **The enclosing repository's tests count too.** SwiftProjectLint's seven nested
        // packages hold no `Tests/` of their own — every one of its ~2,960 snippets lives in the
        // ROOT package's tests — so harvesting the scanned package alone found nothing for the 50
        // stubs that needed it, while SwiftEffectInference (tests in its own package) worked.
        self.testRoots = Self.testDirectories(of: packageRoot)
            + (Self.outermostPackageRoot(from: packageRoot).map(Self.testDirectories) ?? [])
        self.destination = generatedRoot
            .appendingPathComponent("SwiftInfer")
            .appendingPathComponent(Self.fileName)
        self.dryRun = dryRun
        self.arm = arm
    }

    /// Test seam: a corpus supplied directly, written nowhere.
    init(corpus: SyntaxSnippetHarvester.Corpus, arm: ReachArm = .baseline, pastTheCap: [String] = []) {
        self.testRoots = []
        self.destination = URL(fileURLWithPath: "/dev/null")
        self.dryRun = true
        self.arm = arm
        self.corpus = corpus
        self.pastTheCap = SnippetIndex(snippets: pastTheCap)
    }

    /// Every top-level directory of `root` whose name ends in `Tests`.
    static func testDirectories(of root: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )) ?? []
        return children.filter { $0.lastPathComponent.hasSuffix("Tests") }
    }

    /// The outermost ancestor that is itself a SwiftPM package, or `nil` when `packageRoot` is
    /// not nested inside one. Bounded so a manifest far up a tree cannot drag in a whole disk.
    static func outermostPackageRoot(from packageRoot: URL, limit: Int = 4) -> URL? {
        var outermost: URL?
        var current = packageRoot
        for _ in 0 ..< limit {
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            if FileManager.default.fileExists(atPath: parent.appendingPathComponent("Package.swift").path) {
                outermost = parent
            }
            current = parent
        }
        return outermost
    }

    /// The generator expression for `typeName`, or `nil` when it is not a node type the corpus
    /// contains — the caller then falls through to its explained `.todo`.
    ///
    /// - Parameter seeds: what the subject's body compares against (`SyntaxSeeds`). Under the baseline
    ///   arm they are ignored. Otherwise a stub with seeds draws through `gen(_:preferring:kinds:)`, and
    ///   under `seeded` its seeds first admit matching snippets from past the cap.
    func generator(for typeName: String, seeds: SyntaxSeeds = SyntaxSeeds()) -> String? {
        let biased = arm.corpus != .baseline && !seeds.isEmpty
        if biased, arm.corpus == .seeded { admit(typeName, seeds: seeds) }
        guard corpus.nodeTypeNames.contains(typeName) || admittedTypeNames.contains(typeName) else { return nil }
        write()
        guard biased else { return "\(Self.typeName).gen(\(typeName).self)" }
        return "\(Self.typeName).gen(\(typeName).self, preferring: \(Self.arrayLiteral(seeds.tokens)), "
            + "kinds: \(Self.arrayLiteral(seeds.kinds)))"
    }

    /// The snippets the file holds: the corpus, then everything seeds admitted, in admission order.
    var snippets: [String] { corpus.snippets + admitted.map(\.snippet) }

    /// Admit the first `admittedPerStub` snippets from past the cap, in file order, that hold a
    /// `typeName` node and a seed (§2.3). Asking twice admits nothing new, so what the file holds does
    /// not depend on how many times, or in what order, stubs ask.
    private func admit(_ typeName: String, seeds: SyntaxSeeds) {
        let present = Set(admitted.map(\.snippet))
        let fresh = pastTheCap.matching(nodeType: typeName, seeds: seeds)
            .prefix(Self.admittedPerStub)
            .filter { !present.contains($0.snippet) }
        for entry in fresh {
            admitted.append(entry)
            admittedTypeNames.formUnion(entry.kinds)
        }
    }

    /// Writes the file when what it holds has changed — once under the baseline arm, and again each
    /// time seeds admit a snippet.
    ///
    /// ⚠ **Under `seeded` the file is shared by every `discover` process that writes to this
    /// generated root** — the funnel runs one per source target — and each process admits only for its
    /// own stubs. So the snippets already in the file are kept, and this process's admissions are added
    /// after them. Writing this process's alone left an earlier process's stubs drawing a node type no
    /// snippet held any more: an empty pool and a trap.
    private func write() {
        guard !dryRun else { return }
        var contents = snippets
        if arm.corpus == .seeded, let existing = try? String(contentsOf: destination, encoding: .utf8) {
            contents = Self.merged(SyntaxSnippetHarvester.snippets(inCorpusFile: existing), adding: contents)
        }
        guard lastWritten != contents else { return }
        lastWritten = contents
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let text = Self.fileContents(snippets: contents, reach: arm.needsReachMachinery)
        try? Data(text.utf8).write(to: destination, options: .atomic)
    }

    /// `existing` in its order, then each of `adding` it lacks, in theirs.
    static func merged(_ existing: [String], adding: [String]) -> [String] {
        var seen = Set(existing)
        return existing + adding.filter { seen.insert($0).inserted }
    }

    /// The corpus file. Each snippet is a raw multi-line literal with enough `#`s that nothing in
    /// it can close the literal or start an interpolation, and with every unprintable character
    /// spelled as an escape (`escapingUnprintables`).
    static func fileContents(snippets: [String], reach: Bool = false) -> String {
        let literals = snippets.map { snippet -> String in
            let hashes = String(repeating: "#", count: rawDelimiterCount(for: snippet))
            let body = escapingUnprintables(snippet, hashes: hashes)
            return "        \(hashes)\"\"\"\n\(body)\n\"\"\"\(hashes)"
        }
        return """
        // Auto-generated by `swift-infer discover --interactive` — do not edit.
        // Swift snippets harvested from this package's own tests, each of which parses without
        // error. Generated laws over SwiftSyntax nodes draw their inputs from here.

        import Foundation
        import PropertyBased
        import SwiftParser
        import SwiftSyntax

        enum \(typeName) {
            static let snippets: [String] = [
        \(literals.joined(separator: ",\n"))
            ]

        \(machinery)\(reach ? "\n\n" + reachMachinery : "")
        }

        """
    }

    /// The corpus type's fixed half: parse once, collect per node type, draw among the results.
    ///
    /// A constant rather than more lines of `fileContents`, which SwiftLint's body-length cap
    /// reached the moment the cache landed in it.
    private static let machinery = """
            private final class Collector<Node: SyntaxProtocol>: SyntaxAnyVisitor {
                var found: [Node] = []

                override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
                    if let match = node.as(Node.self) { found.append(match) }
                    return .visitChildren
                }
            }

            /// ⚠ **Parsed once, collected once per node type.** A stub calls `gen(_:)` inside its
            /// per-trial closure, so a corpus re-parsed per call costs trials × snippets parses —
            /// measured at over a million for one package, which reads as a hang rather than as
            /// a slow generator.
            private static let trees: [SourceFileSyntax] = snippets.map { Parser.parse(source: $0) }

            private final class Cache: @unchecked Sendable {
                private let lock = NSLock()
                private var storage: [ObjectIdentifier: Any] = [:]

                func nodes<Node: SyntaxProtocol>(_ type: Node.Type, build: () -> [Node]) -> [Node] {
                    lock.lock()
                    defer { lock.unlock() }
                    if let hit = storage[ObjectIdentifier(type)] as? [Node] { return hit }
                    let built = build()
                    storage[ObjectIdentifier(type)] = built
                    return built
                }
            }

            private static let cache = Cache()

            /// Every node of type `Node` in the corpus, in source order.
            static func nodes<Node: SyntaxProtocol>(_ type: Node.Type) -> [Node] {
                cache.nodes(type) {
                    trees.flatMap { tree -> [Node] in
                        let collector = Collector<Node>(viewMode: .sourceAccurate)
                        collector.walk(tree)
                        return collector.found
                    }
                }
            }

            /// A generator drawing among every `Node` the corpus contains. The tool offers this
            /// only for a type it found at least once, so the range is never empty.
            static func gen<Node: SyntaxProtocol>(_ type: Node.Type) -> Generator<Node, some SendableSequenceType> {
                let all = nodes(type)
                return Gen<Int>.int(in: 0 ... max(all.count - 1, 0)).map { all[$0] }
            }
    """

    /// `snippet` with each ASCII control character except tab and newline, and DEL, spelled as a
    /// raw-string escape — `\#u{7}` under one `#` — so the literal still means `snippet`.
    ///
    /// ⚠ **A snippet that parses can still hold a character no string literal may hold raw.**
    /// SwiftUMLStudio's tests feed their renderer a form feed on a line of its own and a BEL inside a
    /// block comment (`\u{0C}`, `\u{07}`), both legal Swift. Written into this file verbatim, each
    /// was `unprintable ASCII character found in source file`, the whole file failed to compile, and
    /// every stub drawing from it went with it. Escaping keeps both: they are exactly the hostile
    /// inputs a totality law wants. A carriage return is escaped too, since a raw one would be read
    /// as a line ending and the snippet would come back changed.
    static func escapingUnprintables(_ snippet: String, hashes: String) -> String {
        var escaped = ""
        for scalar in snippet.unicodeScalars {
            let isControl = (scalar.value < 0x20 && scalar != "\t" && scalar != "\n") || scalar.value == 0x7F
            if isControl {
                escaped += "\\\(hashes)u{\(String(scalar.value, radix: 16, uppercase: true))}"
            } else {
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }

    /// The fewest `#`s such that `"""` + hashes and `\` + hashes never occur in `snippet`.
    static func rawDelimiterCount(for snippet: String) -> Int {
        var count = 1
        while snippet.contains("\"\"\"" + String(repeating: "#", count: count))
                || snippet.contains("\\" + String(repeating: "#", count: count)) {
            count += 1
        }
        return count
    }
}
