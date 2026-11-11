import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// Thread stack sizes seen by the parse hook, from whichever worker ran it.
final class StackSizes: @unchecked Sendable {
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

/// The construction-universe suites share this suite's fixtures and helpers under a short name.
typealias Wiring = ConstructionPurityWiringTests

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
        let makeFunction = try #require(Self.function(named: "make", in: tree))
        let witness = PackagePurity.selfContained(tree).oracle.inferrerRefutation(for: makeFunction)
        guard case .refutingConstruction(type: "Item", via: .storedProperty("id"), cause: _) = witness else {
            Issue.record("expected a construction witness through `Item.id`, got \(String(describing: witness))")
            return
        }
    }

    @Test("constructing a sibling target's identity-minting type refutes the constructor")
    func siblingTargetConstructionRefutes() throws {
        let root = try Self.makePackage([
            "Sources/Model/Item.swift": Self.item,
            "Sources/Lib/Make.swift": Self.make,
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
            "Tests/LibTests/Item.swift": "struct Item { let id = UUID(); let title: String }",
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
            """,
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
    static let nodeIdentityPackage = [
        "Sources/One/A.swift": """
        struct Token { let x: Int; init() { x = 0 } }
        struct A { var value: Token; mutating func reset() { value = .init() } }
        """,
        "Sources/Two/A.swift": """
        struct Stamp { let id = UUID() }
        struct A { var value: Stamp }
        """,
    ]

    @Test("the scan judges the very trees the facts were built from")
    func scanJudgesOnTheFactsOwnNodes() throws {
        let root = try Self.makePackage(Self.nodeIdentityPackage)
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

    /// The node-identity subject above, through BOTH directory overloads — the default one the CLI
    /// calls, which builds its own purity, and the one handed a purity. Only the very node the facts
    /// were built from types `reset`'s `value = .init()` as `One`'s `Token`; a re-parse makes every
    /// `A.value` a candidate, `Two`'s identity-minting `Stamp` among them. So `.pure` here IS the
    /// reuse, observed — a tree merely present in the universe would not show it.
    @Test("every judged file in the universe is judged on the universe's tree")
    func scanReusesTheFactsTrees() throws {
        let root = try Self.makePackage(Self.nodeIdentityPackage)
        defer { try? FileManager.default.removeItem(at: root) }
        let one = root.appendingPathComponent("Sources/One")
        let purity = PackagePurity.forScan(of: one)
        #expect(purity.universe == ["Sources/One/A.swift", "Sources/Two/A.swift"])
        for file in SwiftSourceFiles.sorted(in: one) {
            #expect(purity.tree(for: file) != nil, "\(file.path) would be re-parsed")
        }
        let viaDefault = try FunctionScanner.scanCorpus(directory: one)
        #expect(Self.verdict("reset", in: viaDefault) == .pure, "scanCorpus(directory:) judged a re-parse")
        let viaPurity = try FunctionScanner.scanCorpus(directory: one, purity: purity)
        #expect(Self.verdict("reset", in: viaPurity) == .pure, "scanCorpus(directory:purity:) judged a re-parse")
    }

    @Test("one source is its own package — its own types, and nobody else's")
    func singleSourceIsSelfContained() {
        let declares = "struct Item { let id = UUID() }\nfunc make() -> Item { Item() }"
        let constructsOnly = "func make() -> Item { Item() }"
        #expect(Self.verdict("make", in: FunctionScanner.scanCorpus(source: declares, file: "A.swift")) == .refuted)
        #expect(Self.verdict("make", in: FunctionScanner.scanCorpus(source: constructsOnly, file: "B.swift")) == .pure)
    }
}
