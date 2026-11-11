import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore

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
            "Tests/Shared/Stamp.swift": "struct Stamp { let at = Date() }",
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

    /// **Bound, then deduplicate** — the type doc's order, and the review's `tests#4`. A link in
    /// `Sources/Lib` to a file of an uncompiled nested package is compiled where the link is, so it
    /// is in; the file's own spelling, `Demo/…`, is bounded out. Deduplicating first kept the
    /// smaller `Demo/…` spelling and then bounded it away, losing the linked production file:
    /// `make` read pure.
    @Test("a link into an uncompiled package is bounded before it is deduplicated")
    func boundBeforeDeduplicating() throws {
        let root = try Wiring.makePackage([
            "Demo/Package.swift": ConstructionUniverseNestedPackageTests.demoManifest,
            "Demo/Sources/Demo/Item.swift": Wiring.item,
            "Sources/Lib/Make.swift": Wiring.make,
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.link("Sources/Lib/Item.swift", in: root, to: "../../Demo/Sources/Demo/Item.swift")
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(ConstructionUniverse.files(forScanOf: lib).map(\.relativePath) == [
            "Sources/Lib/Item.swift", "Sources/Lib/Make.swift"
        ])
        #expect(try Self.verdict("make", scanning: lib) == .refuted)
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
            "Sources/Model/Item.swift": "public struct Item: Equatable { public let title: String }",
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
            "Sources/Lib/Make.swift": Wiring.make,
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
