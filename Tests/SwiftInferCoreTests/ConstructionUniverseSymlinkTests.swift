import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **Symlinks and the universe** — the shared spec's amendments A and D (and C, what a walked file
/// must decode as).
///
/// A: a symlinked file is classified where the link is, and two entries that are one file on
/// disk collapse to the one with the smallest relative path — a rule on the paths, never on the
/// order a directory listing happens to return them in.
///
/// D: a scan's root is found from the scanned path AS GIVEN, so a symlinked `Sources/<target>` is
/// judged under the package holding the link, with that package's real sibling targets — and
/// only resolved afterwards, as a key.
private typealias Wiring = ConstructionPurityWiringTests

@Suite("Construction universe — symlinks")
struct ConstructionUniverseSymlinkTests {

    static func link(_ path: String, in root: URL, to destination: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    static func member(_ relativePath: String, key: String) -> ConstructionUniverse.Member {
        let url = URL(fileURLWithPath: "/x/" + relativePath)
        return ConstructionUniverse.Member(relativePath: relativePath, url: url, key: key)
    }

    static func verdict(_ name: String, scanning directory: URL) throws -> PurityVerdict? {
        Wiring.verdict(name, in: try FunctionScanner.scanCorpus(directory: directory))
    }

    // MARK: - A: one entry per file, the smallest path

    @Test("of two spellings of one file, the smallest relative path is kept, whichever arrives first")
    func deduplicationKeepsTheSmallestPath() {
        let zed = Self.member("Sources/Zed/Item.swift", key: "/r/Sources/Zed/Item.swift")
        let alias = Self.member("Sources/Lib/Alias.swift", key: "/r/Sources/Zed/Item.swift")
        let other = Self.member("Sources/AM/Item.swift", key: "/r/Sources/AM/Item.swift")
        for arrival in [[zed, alias, other], [alias, zed, other], [other, zed, alias]] {
            let kept = ConstructionUniverse.ordered(ConstructionUniverse.deduplicated(arrival))
            let paths = kept.map(\.relativePath)
            #expect(paths == ["Sources/AM/Item.swift", "Sources/Lib/Alias.swift"], "\(arrival.map(\.relativePath))")
        }
    }

    @Test("a symlinked file is classified where the link is, and kept at its smallest spelling")
    func symlinkedFileIsKeptAtItsSmallestSpelling() throws {
        let root = try Wiring.makePackage([
            "Sources/Zed/Item.swift": "struct Item { let id = UUID() }",
            "Tests/Shared/Stamp.swift": "struct Stamp { let at = Date() }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.link("Sources/Lib/Alias.swift", in: root, to: "../Zed/Item.swift")
        // A link INTO a test directory is compiled where the link is, so it is production.
        try Self.link("Sources/Lib/Stamp.swift", in: root, to: "../../Tests/Shared/Stamp.swift")
        // A link from a test directory to a production file is not a second production entry.
        try Self.link("Tests/LibTests/Item.swift", in: root, to: "../../Sources/Zed/Item.swift")
        let universe = ConstructionUniverse.files(forScanOf: root.appendingPathComponent("Sources/Lib"))
        #expect(universe.map(\.relativePath) == ["Sources/Lib/Alias.swift", "Sources/Lib/Stamp.swift"])
    }

    // MARK: - D: the root is found from the path as given

    /// The review's reproduction: `Sources/Lib` links outside the package, and the refuting `Item`
    /// lives in a REAL sibling target. Resolving first rooted the table at the link's destination,
    /// which has no `Item`, and advised `make` pure.
    @Test("a symlinked target is judged with its package's real sibling targets")
    func symlinkedTargetSeesItsRealSiblings() throws {
        let outside = try Wiring.makePackage(
            ["Lib/Make.swift": Wiring.make], manifest: false
        )
        defer { try? FileManager.default.removeItem(at: outside) }
        let root = try Wiring.makePackage(["Sources/Model/Item.swift": Wiring.item])
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.link("Sources/Lib", in: root, to: outside.appendingPathComponent("Lib").path)
        let lib = root.appendingPathComponent("Sources/Lib")

        let purity = PackagePurity.forScan(of: lib)
        #expect(purity.root?.path == ConstructionUniverse.resolved(root).path, "judged under the link's destination")
        // The link's files join under the link's spelling, beside the real target.
        #expect(purity.universe == ["Sources/Lib/Make.swift", "Sources/Model/Item.swift"])
        for file in SwiftSourceFiles.sorted(in: lib) {
            #expect(purity.tree(for: file) != nil, "\(file.path) would be judged on a re-parse")
        }
        #expect(try Self.verdict("make", scanning: lib) == .refuted)
        // The control: the destination scanned as itself is its own universe, with no `Item`.
        let alone = try FunctionScanner.scanCorpus(directory: outside.appendingPathComponent("Lib"))
        #expect(Wiring.verdict("make", in: alone) == .pure)
    }

    /// A target linked from ANOTHER package's `Sources/` is judged where the link is: the package
    /// that compiles it. Resolving first judged it under the foreign package's table.
    @Test("a target linked into another package's Sources is judged under the package holding the link")
    func linkIntoAnotherPackageIsJudgedWhereTheLinkIs() throws {
        let foreign = try Wiring.makePackage([
            "Sources/Lib/Make.swift": Wiring.make,
            "Sources/Model/Item.swift": "public struct Item: Equatable { public let title: String }"
        ])
        defer { try? FileManager.default.removeItem(at: foreign) }
        let root = try Wiring.makePackage(["Sources/Model/Item.swift": Wiring.item])
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.link("Sources/Lib", in: root, to: foreign.appendingPathComponent("Sources/Lib").path)
        let lib = root.appendingPathComponent("Sources/Lib")

        let purity = PackagePurity.forScan(of: lib)
        #expect(purity.root?.path == ConstructionUniverse.resolved(root).path)
        #expect(purity.universe == ["Sources/Lib/Make.swift", "Sources/Model/Item.swift"])
        #expect(try Self.verdict("make", scanning: lib) == .refuted)
        // The same files scanned at their real location belong to the foreign package, whose
        // `Item` mints nothing.
        let real = try FunctionScanner.scanCorpus(directory: foreign.appendingPathComponent("Sources/Lib"))
        #expect(Wiring.verdict("make", in: real) == .pure)
    }

    /// The fallback: no ancestor of the path as given holds a manifest, so the walk is retried from
    /// the resolved path and finds the package the link points into.
    @Test("a link from outside every package finds the package it points into")
    func linkFromOutsideEveryPackageFindsItsPackage() throws {
        let root = try Wiring.makePackage([
            "Sources/Model/Item.swift": Wiring.item,
            "Sources/Lib/Make.swift": Wiring.make
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let elsewhere = try Wiring.makePackage([:], manifest: false)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        try Self.link("Lib", in: elsewhere, to: root.appendingPathComponent("Sources/Lib").path)
        let link = elsewhere.appendingPathComponent("Lib")

        #expect(ConstructionUniverse.root(forScanOf: link).path == ConstructionUniverse.resolved(root).path)
        #expect(try Self.verdict("make", scanning: link) == .refuted)
    }
}

// MARK: - C: strict UTF-8

extension ConstructionUniverseSymlinkTests {

    /// The shared spec's amendment C: a file enters the table only if it decodes as strict UTF-8,
    /// since `swiftc` reads no other. A lenient read would detect this UTF-16 file by its byte-order
    /// mark, decode it, and let a type no target compiles refute `make`.
    @Test("a universe file that is not strict UTF-8 declares nothing to the table")
    func nonUTF8FileIsNotInTheUniverse() throws {
        let root = try Wiring.makePackage(["Sources/Lib/Make.swift": Wiring.make])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("Sources/Model/Item.swift")
        let directory = model.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Wiring.item.write(to: model, atomically: true, encoding: .utf16)
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(ConstructionUniverse.files(forScanOf: lib).map(\.relativePath).contains("Sources/Model/Item.swift"))
        let purity = PackagePurity.forScan(of: lib)
        #expect(purity.universe == ["Sources/Lib/Make.swift"], "a UTF-16 file reached the table")
        #expect(try Self.verdict("make", scanning: lib) == .pure)
    }
}

// MARK: - The order, pinned exactly

extension ConstructionUniverseSymlinkTests {

    /// **`String <`, and nothing near it.** The review's mutant sorted with
    /// `localizedStandardCompare` — case-insensitive and numeric — and every suite stayed green:
    /// their paths sorted the same under either. Here they do not (`B` < `F10` < `F2` < `Lib` < `a`
    /// under `String <`; `a`, `B`, `F2`, `F10`, `Lib` under Finder's order), and two pairs of
    /// same-named types carry different witnesses, so the order decides which witness SEI reports
    /// first for each: the clock (`B`'s `Stamp`, `F10`'s `Mark`), not the identifier.
    @Test("the universe is ordered by String <, and the order decides each witness")
    func universeOrderIsStringLessThan() throws {
        let files = [
            "Sources/B/Stamp.swift": "struct Stamp { let at = Date() }",
            "Sources/a/Stamp.swift": "struct Stamp { let id = UUID() }",
            "Sources/F10/Mark.swift": "struct Mark { let at = Date() }",
            "Sources/F2/Mark.swift": "struct Mark { let id = UUID() }",
            "Sources/Lib/Make.swift": "func makeStamp() -> Stamp { Stamp() }\nfunc makeMark() -> Mark { Mark() }"
        ]
        let root = try Wiring.makePackage(files)
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        let purity = PackagePurity.forScan(of: lib)
        let expected = [
            "Sources/B/Stamp.swift", "Sources/F10/Mark.swift", "Sources/F2/Mark.swift",
            "Sources/Lib/Make.swift", "Sources/a/Stamp.swift"
        ]
        #expect(purity.universe == expected)

        // The fixture can fail: Finder's order builds a different digest.
        let digest = { (order: [String]) -> [String] in
            let facts = ConstructionFacts.build(from: order.map { Parser.parse(source: files[$0] ?? "") })
            return facts.refutedTypeNames.map { "\($0): \(facts.refutation(constructing: $0)?.description ?? "?")" }
        }
        let finder = expected.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        #expect(digest(finder) != digest(expected), "the fixture must be order-sensitive, or this test cannot fail")
        #expect(purity.refutedTypes == digest(expected))

        let tree = try #require(purity.tree(for: lib.appendingPathComponent("Make.swift")))
        for (name, type) in [("makeStamp", "Stamp"), ("makeMark", "Mark")] {
            let function = try #require(Wiring.function(named: name, in: tree))
            #expect(purity.oracle.verdict(for: function) == .refuted)
            let witness = purity.oracle.inferrerRefutation(for: function)
            guard case .refutingConstruction(type: type, via: .storedProperty("at"), cause: _) = witness else {
                let got = String(describing: witness)
                Issue.record("\(name): expected the clock witness of the first `\(type)` in String < order, got \(got)")
                continue
            }
        }
    }
}
