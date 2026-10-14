import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore

private typealias Wiring = ConstructionPurityWiringTests

/// **The scanned path in its on-disk letter case** — the shared spec's amendment L. On a volume that
/// folds case a mis-cased `--sources` opens the same directory, so it must build the same universe:
/// the predicate reads names (`MyTests` is a test directory, `Mytests` is not), and the build order and
/// SEI's first witness follow the spelling. Each case is the joint review's reproduction; all of
/// them need a case-insensitive temporary volume, APFS's default, and are skipped on any other.
@Suite(
    "Construction universe — the scanned path's letter case",
    .enabled(if: ConstructionUniverseDependencyPathTests.temporaryVolumeIgnoresCase)
)
struct ConstructionUniverseLetterCaseTests {

    static let logic = """
    func make(_ title: String) -> Item { Item(title: title) }
    func double(_ n: Int) -> Int { n * 2 }
    """

    /// `sip#1` (a): `Mytests/X` — production by the predicate — scanned as `MyTests/X`. Spelled as
    /// typed, `MyTests` made the scan self-contained, the package's UUID-minting `Item` left its
    /// table, and `make` was advised pure. (The reproduction was `tests/X` scanned as `Tests/X`;
    /// since amendment 5, `tests` is a test suite's folder in either case, so a name only the letter
    /// case makes a test target's stands in.)
    @Test("a production directory scanned through a test-directory spelling joins its package")
    func misCasedTestSpellingStillFindsThePackage() throws {
        let root = try Wiring.makePackage([
            "Sources/Model/Item.swift": Wiring.item,
            "Mytests/X/Logic.swift": Self.logic
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let typed = root.appendingPathComponent("MyTests/X")
        #expect(ConstructionUniverse.root(forScanOf: typed).path == ConstructionUniverse.resolved(root).path)
        #expect(ConstructionUniverse.files(forScanOf: typed).map(\.relativePath) == [
            "Mytests/X/Logic.swift", "Sources/Model/Item.swift"
        ])
        #expect(try ConstructionUniverseNestedPackageTests.verdict("make", scanning: typed) == .refuted)
    }

    /// `sip#1` (b): a real fixture under `MyTests/Fixtures/X`, with its own plain `Item`, scanned as
    /// `Mytests/fixtures/x`. Spelled as typed, `Mytests` is no test directory, so the scan walked up
    /// to the package, the fixture joined its universe as production, and the package's namesake
    /// `Item` refuted the fixture's `make`. (Reproduced with `Tests` and `tests` before amendment 5.)
    @Test("a test fixture scanned through a production spelling stays its own project")
    func misCasedProductionSpellingStaysSelfContained() throws {
        let root = try Wiring.makePackage([
            "Sources/Model/Item.swift": Wiring.item,
            "MyTests/Fixtures/X/Item.swift": "struct Item { let title: String }",
            "MyTests/Fixtures/X/Logic.swift": Self.logic
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let typed = root.appendingPathComponent("Mytests/fixtures/x")
        let fixture = root.appendingPathComponent("MyTests/Fixtures/X")
        #expect(ConstructionUniverse.root(forScanOf: typed).path == ConstructionUniverse.resolved(fixture).path)
        #expect(ConstructionUniverse.files(forScanOf: typed).map(\.relativePath) == ["Item.swift", "Logic.swift"])
        #expect(try ConstructionUniverseNestedPackageTests.verdict("make", scanning: typed) == .pure)
    }

    /// `agreement#3`: two `Row`s, one minting a `Date`, one a `UUID`. Scanned as `Sources/APP`, the
    /// member was spelled `Sources/APP/Row.swift`, which sorts before `Sources/AQ/…` where the
    /// on-disk `Sources/App/…` sorts after — so SEI reported the other witness, and the digest
    /// differed from SwiftProjectLint's for the same tree.
    @Test("a mis-cased scan builds the universe, the order and the witness of the on-disk spelling")
    func misCasedScanIsSpelledOnDisk() throws {
        let root = try Wiring.makePackage([
            "Sources/App/Row.swift": """
            import Foundation
            struct Row { let stamp = Date() }
            func make() -> Row { Row() }
            """,
            "Sources/AQ/Rival.swift": "import Foundation\nstruct Row { let stamp = UUID() }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let onDisk = PackagePurity.forScan(of: root.appendingPathComponent("Sources/App"))
        for typed in ["Sources/APP", "SOURCES/app", "sources/App"] {
            let purity = PackagePurity.forScan(of: root.appendingPathComponent(typed))
            #expect(purity.universe == ["Sources/AQ/Rival.swift", "Sources/App/Row.swift"], "\(typed)")
            #expect(purity.refutedTypes == onDisk.refutedTypes, "\(typed)")
            #expect(onDisk.covers(root.appendingPathComponent(typed)), "\(typed)")
        }
    }

    @Test("each component takes its on-disk name, a symlink keeps its own")
    func onDiskNameIsTheListingsName() {
        #expect(ConstructionUniverse.onDiskName(of: "SOURCES", among: ["Package.swift", "Sources"]) == "Sources")
        #expect(ConstructionUniverse.onDiskName(of: "a", among: ["A", "a"]) == "a", "the exact name wins")
        #expect(ConstructionUniverse.onDiskName(of: "x", among: ["A", "a"]) == "x", "no match keeps the name")
        #expect(ConstructionUniverse.onDiskName(of: "B", among: ["b", "b"]) == "B", "two matches keep the name")
    }
}
