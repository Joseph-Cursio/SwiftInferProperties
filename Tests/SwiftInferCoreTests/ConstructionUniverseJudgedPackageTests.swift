import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore

private typealias Wiring = ConstructionPurityWiringTests
private typealias Nested = ConstructionUniverseNestedPackageTests

/// **A package the scan judges is in its universe** — the shared spec's amendment J. A nested
/// package holding a judged file is in, with its own local-dependency closure, whether or not the
/// root compiles it: a function is judged with its own package's types.
@Suite("Construction universe — the packages a scan judges")
struct ConstructionUniverseJudgedPackageTests {

    static let item = """
    import Foundation
    public struct Item: Equatable { public let id = UUID(); public let n: Int; public init(n: Int) { self.n = n } }
    """
    static let callers = """
    public func normalized(_ item: Item) -> Item { Item(n: abs(item.n)) }
    public func clamp(_ value: Int) -> Int { min(max(value, 0), 10) }
    """

    /// The review's `robustness#1` (`fx/sip-inc-nested`): the root compiles only `App`, and
    /// `Examples/Demo` is a package of its own. `discover --sources Examples` judges Demo's
    /// `normalized`, which builds a UUID-minting `Item` — and the bound took Demo's files out of the
    /// table, so `normalized` read pure and an idempotence law was proposed over it.
    @Test("a scan over an uncompiled nested package judges it with its own types")
    func judgedNestedPackageIsInItsUniverse() throws {
        let root = try Wiring.makePackage([
            "Examples/Demo/Package.swift": Nested.demoManifest,
            "Examples/Demo/Sources/Demo/Item.swift": Self.item,
            "Examples/Demo/Sources/Demo/Callers.swift": Self.callers,
            "Sources/App/Plain.swift": "public func appPlain(_ n: Int) -> Int { n * 2 }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let examples = root.appendingPathComponent("Examples")
        #expect(ConstructionUniverse.files(forScanOf: examples).map(\.relativePath) == [
            "Examples/Demo/Sources/Demo/Callers.swift", "Examples/Demo/Sources/Demo/Item.swift",
            "Sources/App/Plain.swift"
        ])
        #expect(try Nested.verdict("normalized", scanning: examples) == .refuted)
        #expect(try Nested.verdict("clamp", scanning: examples) == .pure, "control: the table refutes only the builder")
        // A scan that judges only the root's own files leaves Demo out, as before.
        let app = root.appendingPathComponent("Sources/App")
        #expect(ConstructionUniverse.files(forScanOf: app).map(\.relativePath) == ["Sources/App/Plain.swift"])
    }

    /// The judged package brings its own closure: Demo depends on `../../Shared`, where `Item` lives,
    /// and no file under the scanned `Examples/` is Shared's.
    @Test("a judged nested package brings its own local dependencies")
    func judgedPackageBringsItsClosure() throws {
        let root = try Wiring.makePackage([
            "Examples/Demo/Package.swift": Nested.manifest(dependingOn: "../../Shared"),
            "Examples/Demo/Sources/Demo/Callers.swift": Self.callers,
            "Shared/Package.swift": Nested.demoManifest,
            "Shared/Sources/Shared/Item.swift": Self.item,
            "Sources/App/Plain.swift": "public func appPlain(_ n: Int) -> Int { n * 2 }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let examples = root.appendingPathComponent("Examples")
        let paths = ConstructionUniverse.files(forScanOf: examples).map(\.relativePath)
        #expect(paths.contains("Shared/Sources/Shared/Item.swift"), "\(paths)")
        #expect(try Nested.verdict("normalized", scanning: examples) == .refuted)
    }

    /// The accepted cost, in the sound direction: a scan of the whole root judges Demo's files, so
    /// Demo is in, and its `Row` refutes the root's namesake again — only when Demo is judged too.
    @Test("a scan that judges the namesake's package takes it, and the namesake refutes")
    func judgingTheNamesakePackageTakesIt() throws {
        let root = try Wiring.makePackage([
            "Sources/Lib/Row.swift": Nested.row,
            "Demo/Package.swift": Nested.demoManifest,
            "Demo/Sources/Demo/main.swift": Nested.mintingRow
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try Nested.verdict("make", scanning: root) == .refuted)
        #expect(try Nested.verdict("make", scanning: root.appendingPathComponent("Sources/Lib")) == .pure)
    }

    /// Two scans under one root can now build different tables, so a value built for one must not
    /// judge the other — the root alone no longer says it covers.
    @Test("a purity built for one scan does not cover a scan that takes another package")
    func purityCoversOnlyItsOwnUniverse() throws {
        let root = try Wiring.makePackage([
            "Examples/Demo/Package.swift": Nested.demoManifest,
            "Examples/Demo/Sources/Demo/Item.swift": Self.item,
            "Examples/Demo/Sources/Demo/Callers.swift": Self.callers,
            "Sources/App/Plain.swift": "public func appPlain(_ n: Int) -> Int { n * 2 }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let app = PackagePurity.forScan(of: root.appendingPathComponent("Sources/App"))
        let examples = root.appendingPathComponent("Examples")
        #expect(!app.covers(examples))
        #expect(throws: FunctionScanner.ScanError.self) {
            try FunctionScanner.scanCorpus(directory: examples, purity: app)
        }
        #expect(PackagePurity.forScan(of: examples).covers(examples))
        #expect(app.covers(root.appendingPathComponent("Sources")), "the same universe from a sibling is not foreign")
    }

    /// `covers` is asked once per directory scan — three times by `discover-reducers` — and a
    /// universe walks the root, `Tests/` included, and parses its closure's manifests: computed
    /// on every ask, it cost 54–699 ms a call. The directory a value was built for is covered by
    /// construction, so it is answered from the record. Pinned by changing the disk under it: a
    /// value that walked again would see a different universe and answer `false`.
    @Test("covers answers for its own directory from the record, without walking")
    func coversItsOwnDirectoryFromTheRecord() throws {
        let root = try Wiring.makePackage([
            "Sources/Model/Item.swift": Wiring.item,
            "Sources/Lib/Make.swift": Wiring.make
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        let purity = PackagePurity.forScan(of: lib)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/Model/Item.swift"))
        #expect(ConstructionUniverse.files(forScanOf: lib).count == 1, "control: the universe on disk changed")
        #expect(purity.covers(lib), "covers walked the root again for the directory it was built for")
        #expect(purity.withoutConstructionFacts.covers(lib))
        // The count is what fails when the shortcut goes, however cheap one universe is: the
        // memo alone would answer asks 2 and 3, and only the record answers ask 1.
        for _ in 0..<3 { #expect(purity.covers(lib)) }
        #expect(purity.coverage.universesComputed == 0, "covers computed a universe for its own directory")
    }

    /// Another directory under the same root is compared in full — once. The answer is
    /// remembered, so the census and the discoverers that ask again pay nothing.
    @Test("covers compares another directory once, and remembers the answer")
    func coversRemembersAnotherDirectory() throws {
        let root = try Wiring.makePackage([
            "Sources/Model/Item.swift": Wiring.item,
            "Sources/Lib/Make.swift": Wiring.make
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let purity = PackagePurity.forScan(of: root.appendingPathComponent("Sources"))
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(purity.covers(lib))
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/Model/Item.swift"))
        #expect(purity.covers(lib), "covers computed the same directory's universe twice")
        #expect(purity.coverage.universesComputed == 1)
        // A directory under another root is foreign without a walk, and stays so.
        let other = try Wiring.makePackage(["Sources/Lib/Make.swift": Wiring.make])
        defer { try? FileManager.default.removeItem(at: other) }
        #expect(!purity.covers(other.appendingPathComponent("Sources/Lib")))
    }

    /// A second root holding an IDENTICAL layout — a speculative snapshot is exactly this — has
    /// the same members, so only the root comparison tells the two apart; judging the copy under
    /// the original's trees would look every file up under the wrong key. `covers` says no, and
    /// says it from `root(forScanOf:)` alone, without computing the copy's universe.
    @Test("covers rejects an identical layout under another root, without a walk")
    func coversRejectsAnIdenticalLayoutElsewhere() throws {
        let files = ["Sources/Model/Item.swift": Wiring.item, "Sources/Lib/Make.swift": Wiring.make]
        let original = try Wiring.makePackage(files)
        defer { try? FileManager.default.removeItem(at: original) }
        let copy = try Wiring.makePackage(files)
        defer { try? FileManager.default.removeItem(at: copy) }
        let purity = PackagePurity.forScan(of: original.appendingPathComponent("Sources/Lib"))
        let copiedLib = copy.appendingPathComponent("Sources/Lib")
        // The control: the copy's universe is member for member the original's.
        #expect(ConstructionUniverse.files(forScanOf: copiedLib).map(\.relativePath) == purity.universe)
        #expect(!purity.covers(copiedLib), "a copy of the package was taken for the package")
        #expect(purity.coverage.universesComputed == 0, "another root was told apart by a walk")
    }
}
