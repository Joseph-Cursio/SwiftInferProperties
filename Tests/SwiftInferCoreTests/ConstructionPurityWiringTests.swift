import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **End to end: a scan builds its project's construction facts once and judges with them.**
///
/// Assertions are on the SUMMARIES a scan emits, not on the facts, because a table that is built
/// and then dropped on the way to the visitor is the failure this suite exists to catch. Every
/// test carries at least one row the table must refute, so each fails on an unconfigured oracle.
@Suite("Construction purity — wired through the scanner")
struct ConstructionPurityWiringTests {

    // MARK: - Fixtures

    /// A package on disk: `Package.swift` (unless `manifest` is false) plus `files`, by
    /// root-relative path. Spelled as `NSTemporaryDirectory()` spells it — `/var/…` on macOS —
    /// which is the spelling the resolved-root tests need.
    static func makePackage(_ files: [String: String], manifest: Bool = true) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ConstructionWiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if manifest {
            try "// swift-tools-version:5.9\n".write(
                to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
            )
        }
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    static func verdict(_ name: String, in corpus: ScannedCorpus) -> PurityVerdict? {
        corpus.summaries.first { $0.name == name }?.purityVerdict
    }

    static func function(named name: String, in tree: SourceFileSyntax) -> FunctionDeclSyntax? {
        CensusFunctionCollector.functions(in: tree).first { $0.name.text == name }
    }

    static let item = "public struct Item: Equatable { public let id = UUID(); public let title: String }"
    static let make = "public func make(_ title: String) -> Item { Item(title: title) }"

    // MARK: - The table reaches the verdict

    @Test("a construction in the same file refutes, with a construction witness")
    func sameFileConstructionRefutes() throws {
        let source = "struct Item { let id = UUID() }\nfunc make() -> Item { Item() }"
        #expect(Self.verdict("make", in: FunctionScanner.scanCorpus(source: source, file: "One.swift")) == .refuted)
        let tree = Parser.parse(source: source)
        let make = try #require(Self.function(named: "make", in: tree))
        let witness = PackagePurity.selfContained(tree).oracle.inferrerRefutation(for: make)
        guard case .refutingConstruction(type: "Item", via: .storedProperty("id"), cause: _) = witness else {
            Issue.record("expected a construction witness through `Item.id`, got \(String(describing: witness))")
            return
        }
    }

    @Test("constructing a sibling target's identity-minting type refutes the constructor")
    func siblingTargetConstructionRefutes() throws {
        let root = try Self.makePackage([
            "Sources/Model/Item.swift": Self.item,
            "Sources/Lib/Make.swift": Self.make
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        let corpus = try FunctionScanner.scanCorpus(directory: lib)
        #expect(Self.verdict("make", in: corpus) == .refuted)
        #expect(corpus.summaries.first { $0.name == "make" }?.isInferredPure == false)
        // The control: the same file alone is not a package, and alone it cannot see `Item`.
        let alone = try FunctionScanner.scanCorpus(file: lib.appendingPathComponent("Make.swift"))
        #expect(Self.verdict("make", in: alone) == .pure, "the package table, not the file, is what refutes")
    }

    @Test("a test file's namesake does not refute a production constructor")
    func testFileNamesakeDoesNotRefute() throws {
        let root = try Self.makePackage([
            "Sources/Lib/Item.swift": "public struct Item: Equatable { public let title: String }",
            "Sources/Lib/Make.swift": Self.make,
            "Sources/Lib/Stamp.swift": """
            public struct Stamp { public let id = UUID() }
            public func stamp() -> Stamp { Stamp() }
            """,
            "Tests/LibTests/Item.swift": "struct Item { let id = UUID(); let title: String }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let corpus = try FunctionScanner.scanCorpus(directory: root.appendingPathComponent("Sources/Lib"))
        #expect(Self.verdict("stamp", in: corpus) == .refuted, "control: the table is live")
        #expect(Self.verdict("make", in: corpus) == .pure, "a test target's `Item` reached the production table")
    }

    /// The `generateRecommendations` shape: the caller constructs nothing itself; an `inout`
    /// helper does, and the one-hop join carries the helper's refutation to it.
    @Test("a helper that constructs is joined one hop to its caller")
    func joinCarriesAConstructionOneHop() throws {
        let root = try Self.makePackage([
            "Sources/Lib/Rec.swift": "public struct Rec { public let id = UUID(); public let title: String }",
            "Sources/Lib/Gen.swift": """
            func appendRec(_ recs: inout [Rec], _ title: String) { recs.append(Rec(title: title)) }
            public func generate(_ titles: [String]) -> Int {
                var recs: [Rec] = []
                for title in titles { appendRec(&recs, title) }
                return recs.count
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        let corpus = try FunctionScanner.scanCorpus(directory: lib)
        #expect(Self.verdict("appendRec", in: corpus) == .refuted)
        #expect(Self.verdict("generate", in: corpus) == .refuted, "PackagePurityJoin retracts the caller")
        let unjoined = try FunctionScanner.scanCorpus(
            file: lib.appendingPathComponent("Gen.swift"), purity: .forScan(of: lib)
        )
        #expect(Self.verdict("generate", in: unjoined) == .pure, "control: alone, the caller names nothing")
    }

    // MARK: - Same trees

    /// SEI types an assignment by the enclosing declaration's own property, matched by NODE
    /// identity. Judged on a re-parse that match fails and every same-named declaration's property
    /// is a candidate — so `reset` would be refuted by the other target's `A`.
    @Test("the scan judges the very trees the facts were built from")
    func scanJudgesOnTheFactsOwnNodes() throws {
        let root = try Self.makePackage([
            "Sources/One/A.swift": """
            struct Token { let x: Int; init() { x = 0 } }
            struct A { var value: Token; mutating func reset() { value = .init() } }
            """,
            "Sources/Two/A.swift": """
            struct Stamp { let id = UUID() }
            struct A { var value: Stamp }
            """
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let one = root.appendingPathComponent("Sources/One")
        let purity = PackagePurity.forScan(of: one)
        #expect(Self.verdict("reset", in: try FunctionScanner.scanCorpus(directory: one, purity: purity)) == .pure)
        // The control: the same file re-parsed, judged under the same facts.
        let file = one.appendingPathComponent("A.swift")
        let reparsed = FunctionScanner.scanCorpus(
            tree: Parser.parse(source: try String(contentsOf: file, encoding: .utf8)),
            file: file.path,
            purity: purity.oracle
        )
        #expect(Self.verdict("reset", in: reparsed) == .refuted)
    }

    @Test("every judged file in the universe is judged on the universe's tree")
    func scanReusesTheFactsTrees() throws {
        let root = try Self.makePackage([
            "Sources/Lib/Item.swift": Self.item,
            "Sources/Lib/Make.swift": Self.make
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        let purity = PackagePurity.forScan(of: lib)
        #expect(purity.universe == ["Sources/Lib/Item.swift", "Sources/Lib/Make.swift"])
        for file in SwiftSourceFiles.sorted(in: lib) {
            #expect(purity.tree(for: file) != nil, "\(file.path) would be re-parsed")
        }
        #expect(Self.verdict("make", in: try FunctionScanner.scanCorpus(directory: lib, purity: purity)) == .refuted)
    }

    @Test("one source is its own package — its own types, and nobody else's")
    func singleSourceIsSelfContained() {
        let declares = "struct Item { let id = UUID() }\nfunc make() -> Item { Item() }"
        let constructsOnly = "func make() -> Item { Item() }"
        #expect(Self.verdict("make", in: FunctionScanner.scanCorpus(source: declares, file: "A.swift")) == .refuted)
        #expect(Self.verdict("make", in: FunctionScanner.scanCorpus(source: constructsOnly, file: "B.swift")) == .pure)
    }
}

// MARK: - The universe, and its order

extension ConstructionPurityWiringTests {

    @Test("the universe rule", arguments: [
        ("Sources/A/x.swift", true),
        ("Tests/ATests/x.swift", false),
        ("FooTests/x.swift", false),
        ("Packages/P/Tests/PTests/x.swift", false),
        ("Packages/P/Sources/P/x.swift", true),
        ("Package.swift", false),
        ("Package@swift-5.9.swift", false),
        ("Packages/P/Package.swift", false),
        (".build/checkouts/x/y.swift", false),
        ("DerivedData/x/y.swift", false),
        ("Pods/x/y.swift", false),
        ("Sources/ATestSupport/x.swift", true),
        ("Sources/A/Mocks.swift", true),
        ("Sources/A/ABTest.swift", true),
        ("fixtures/x/Sources/X/y.swift", true),
        ("Sources/A/README.md", false)
    ])
    func universeRule(path: String, expected: Bool) {
        #expect(ConstructionUniverse.isProductionSource(relativePath: path) == expected)
    }

    @Test("a scan under a test directory is its own project")
    func testDirectoryScanIsSelfContained() throws {
        let root = try Self.makePackage([
            "Sources/Lib/Big.swift": "public struct Big { public let title: String }",
            "Tests/Fixtures/X/Item.swift": "struct Item { let id = UUID() }",
            "Tests/Fixtures/X/Make.swift": "func make() -> Item { Item() }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appendingPathComponent("Tests/Fixtures/X")
        let resolvedFixture = fixture.standardizedFileURL.resolvingSymlinksInPath()
        #expect(ConstructionUniverse.root(forScanOf: fixture).path == resolvedFixture.path)
        let purity = PackagePurity.forScan(of: fixture)
        #expect(purity.universe == ["Item.swift", "Make.swift"], "the package's Sources were parsed")
        #expect(Self.verdict("make", in: try FunctionScanner.scanCorpus(directory: fixture)) == .refuted)
    }

    @Test("a symlinked target is judged under its own files' facts, on the universe's trees")
    func symlinkedTargetIsInUniverse() throws {
        let outside = try Self.makePackage([
            "Foo/Item.swift": "struct Item { let id = UUID() }",
            "Foo/Make.swift": "func make() -> Item { Item() }"
        ], manifest: false)
        defer { try? FileManager.default.removeItem(at: outside) }
        let root = try Self.makePackage(["Sources/Other/Other.swift": "struct Other {}"])
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("Sources/Foo")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.appendingPathComponent("Foo"))

        let purity = PackagePurity.forScan(of: link)
        let itemRefuted = purity.refutedTypes.contains { $0.hasPrefix("Item:") }
        #expect(itemRefuted, "the symlinked target's types are not in the table")
        for file in SwiftSourceFiles.sorted(in: link) {
            #expect(purity.tree(for: file) != nil, "\(file.path) is judged on a re-parse")
        }
        #expect(Self.verdict("make", in: try FunctionScanner.scanCorpus(directory: link)) == .refuted)
    }

    @Test("a root spelled /var is resolved, and its trees are found under either spelling")
    func rootSpellingIsResolved() throws {
        let root = try Self.makePackage(["Sources/Lib/Item.swift": Self.item, "Sources/Lib/Make.swift": Self.make])
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.path.hasPrefix("/private/") ? String(root.path.dropFirst("/private".count)) : root.path
        let lib = URL(fileURLWithPath: path).appendingPathComponent("Sources/Lib")
        let purity = PackagePurity.forScan(of: lib)
        // Both spellings resolve to one root — the one the value records.
        #expect(purity.root?.path == URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
        #expect(purity.root?.path == root.resolvingSymlinksInPath().path)
        #expect(purity.universe.count == 2)
        for file in SwiftSourceFiles.sorted(in: lib) {
            #expect(purity.tree(for: file) != nil, "\(file.path) not found under the resolved key")
        }
        #expect(Self.verdict("make", in: try FunctionScanner.scanCorpus(directory: lib, purity: purity)) == .refuted)
    }

    @Test("a purity built for another project is rejected, never used")
    func foreignPurityIsRejected() throws {
        let first = try Self.makePackage(["Sources/Lib/Item.swift": Self.item, "Sources/Lib/Make.swift": Self.make])
        defer { try? FileManager.default.removeItem(at: first) }
        let second = try Self.makePackage(["Sources/Lib/Other.swift": "public struct Other {}"])
        defer { try? FileManager.default.removeItem(at: second) }
        let foreign = PackagePurity.forScan(of: second.appendingPathComponent("Sources/Lib"))
        let lib = first.appendingPathComponent("Sources/Lib")
        #expect(throws: FunctionScanner.ScanError.self) {
            try FunctionScanner.scanCorpus(directory: lib, purity: foreign)
        }
        #expect(throws: FunctionScanner.ScanError.self) {
            try FunctionScanner.scanCorpus(directory: lib, purity: .unconfigured)
        }
        // The same project's value, built for a sibling directory, is not foreign.
        let sibling = PackagePurity.forScan(of: first.appendingPathComponent("Sources"))
        #expect(Self.verdict("make", in: try FunctionScanner.scanCorpus(directory: lib, purity: sibling)) == .refuted)
    }

    /// **The stack-depth trap, closed for the universe parse.** A parse recurses about ten frames
    /// per nesting level; a GCD worker or a swift-testing thread has ~512 KB, and overflowing it is
    /// `SIGBUS` — the whole process, not one test. The first parallel parse used
    /// `concurrentPerform` and the batch-2 census died exactly so. The hook records the stack of
    /// every thread that parses; the deep sibling file is the realistic witness (nesting 19, just
    /// under a debug parser's limit of 20), and it is parsed and built from, never judged here.
    @Test("the universe is parsed on large-stack threads, deep source included")
    func universeIsParsedOnLargeStacks() throws {
        var deep = "Item()"
        for _ in 0..<9 { deep = "f({ g(\(deep)) })" }
        let root = try Self.makePackage([
            "Sources/Model/Item.swift": "struct Item { let id = UUID() }",
            "Sources/Model/Deep.swift": """
            func f(_ x: () -> Any) -> Any { x() }
            func g(_ x: Any) -> Any { x }
            let deep = \(deep)
            """,
            "Sources/Lib/Make.swift": "func make() -> Item { Item() }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        let stacks = StackSizes()
        let purity = PackagePurity.forScan(of: lib) { urls in
            PackagePurity.parseInParallel(urls) { _ in stacks.record(Thread.current.stackSize) }
        }
        #expect(stacks.all.count == 3)
        #expect(stacks.all.allSatisfy { $0 >= LargeStackWorkers.stackSize }, "parsed on \(stacks.all) byte stacks")
        #expect(purity.universe.contains("Sources/Model/Deep.swift"))
        #expect(Self.verdict("make", in: try FunctionScanner.scanCorpus(directory: lib, purity: purity)) == .refuted)
    }

    /// The parse is parallel; the build is not allowed to notice. SEI's alias resolution takes
    /// the first target, so two same-named aliases make the table order-sensitive — which is
    /// what makes this fixture able to fail.
    @Test("the build order is the universe order, whatever order the parses finish in")
    func buildOrderIsUniverseOrder() throws {
        let root = try Self.makePackage([
            "Sources/A/A.swift": """
            struct A { typealias Stamp = String; var s: Stamp = .init() }
            func makeA() -> A { A() }
            """,
            "Sources/B/B.swift": """
            struct B { typealias Stamp = UUID; let s: Stamp = .init() }
            func makeB() -> B { B() }
            """,
            "Sources/C/C.swift": "struct C { let id = UUID() }\nfunc makeC() -> C { C() }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("Sources")
        let baseline = PackagePurity.forScan(of: sources)
        #expect(!baseline.refutedTypes.isEmpty, "the fixture must refute something, or order cannot show")
        #expect(baseline.universe == baseline.universe.sorted())

        // Later slots finish first: the stub delays each parse by its distance from the end.
        let reversed = PackagePurity.forScan(of: sources) { urls in
            PackagePurity.parseInParallel(urls) { index in usleep(UInt32((urls.count - index) * 20_000)) }
        }
        let runs = (0..<3).map { _ in PackagePurity.forScan(of: sources) } + [reversed]
        // SEI's first witness per function, on each run's own trees.
        let witnesses = { (purity: PackagePurity) -> [String] in
            SwiftSourceFiles.sorted(in: sources).flatMap { file -> [String] in
                guard let tree = purity.tree(for: file) else { return ["\(file.lastPathComponent): no tree"] }
                return CensusFunctionCollector.functions(in: tree).map {
                    "\($0.name.text): \(purity.oracle.inferrerRefutation(for: $0)?.description ?? "none")"
                }
            }
        }
        for run in runs {
            #expect(run.refutedTypes == baseline.refutedTypes)
            #expect(run.universe == baseline.universe)
            #expect(witnesses(run) == witnesses(baseline))
        }
    }
}

/// Thread stack sizes seen by the parse hook, from whichever worker ran it.
private final class StackSizes: @unchecked Sendable {
    private let lock = NSLock()
    private var sizes: [Int] = []

    func record(_ size: Int) {
        lock.lock()
        sizes.append(size)
        lock.unlock()
    }

    var all: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return sizes
    }
}
