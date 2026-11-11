import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

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
        ("test/Parse/x.swift", false),
        ("validation-test/stdlib/x.swift", false),
        ("Sources/swift-test/x.swift", true),
        ("Sources/A/README.md", false),
    ])
    func universeRule(path: String, expected: Bool) {
        #expect(ConstructionUniverse.isProductionSource(relativePath: path) == expected)
    }

    @Test("a scan under a test directory is its own project")
    func testDirectoryScanIsSelfContained() throws {
        let root = try Self.makePackage([
            "Sources/Lib/Big.swift": "public struct Big { public let title: String }",
            "Tests/Fixtures/X/Item.swift": "struct Item { let id = UUID() }",
            "Tests/Fixtures/X/Make.swift": "func make() -> Item { Item() }",
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
            "Foo/Make.swift": "func make() -> Item { Item() }",
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
            "Sources/Lib/Make.swift": "func make() -> Item { Item() }",
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

    /// The parse is parallel; the build is not allowed to notice. Two targets each declare
    /// `Stamp` with its own witness, and SEI reports the first declaration it read, so the table's
    /// digest is order-sensitive — which is what makes this fixture able to fail. (Two same-named
    /// typealiases did that until SEI `9d0bf6d`, which follows every alias a name may mean.)
    @Test("the build order is the universe order, whatever order the parses finish in")
    func buildOrderIsUniverseOrder() throws {
        let stampA = "struct Stamp { let id = UUID() }\nfunc makeA() -> Stamp { Stamp() }"
        let stampB = "struct Stamp { let at = Date() }\nfunc makeB() -> Stamp { Stamp() }"
        let digest = { (trees: [SourceFileSyntax]) -> [String] in
            let facts = ConstructionFacts.build(from: trees)
            return facts.refutedTypeNames.map { "\($0): \(facts.refutation(constructing: $0)?.description ?? "?")" }
        }
        let parsedA = Parser.parse(source: stampA)
        let parsedB = Parser.parse(source: stampB)
        #expect(
            digest([parsedA, parsedB]) != digest([parsedB, parsedA]),
            "the fixture must be order-sensitive, or this test cannot fail"
        )
        let root = try Self.makePackage([
            "Sources/A/Stamp.swift": stampA,
            "Sources/B/Stamp.swift": stampB,
            "Sources/C/C.swift": "struct C { let id = UUID() }\nfunc makeC() -> C { C() }",
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
