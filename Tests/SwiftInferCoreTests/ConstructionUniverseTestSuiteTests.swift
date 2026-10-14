import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore

private typealias Wiring = ConstructionPurityWiringTests

/// **A test suite's folder** — the shared spec's amendment 5 (W). The swift compiler keeps its tests
/// in `test/` and `validation-test/`, one test program per file, and with no root manifest all
/// 22,600 of them were one table: every name had a namesake, and the facts did not finish building.
/// A suite's folder is test code, as a test target's is, by its exact name; a scan under it is its
/// own project, as a scan under `Tests/` is.
@Suite("Construction universe — a test suite's folder")
struct ConstructionUniverseTestSuiteTests {

    @Test("a test suite's types stay out of the package's table, and a scan under it is its own project")
    func testSuiteIsOutOfTheUniverse() throws {
        let root = try Wiring.makePackage([
            "Sources/Lib/Item.swift": "struct Item { let n: Int }",
            "Sources/Lib/Make.swift": "func make() -> Item { Item(n: 1) }",
            "test/Parse/Item.swift": "struct Item { let n: Int; let id = UUID() }",
            "test/Parse/Build.swift": "func build() -> Item { Item(n: 1) }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(PackagePurity.forScan(of: root).universe == ["Sources/Lib/Item.swift", "Sources/Lib/Make.swift"])
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(Wiring.verdict("make", in: try FunctionScanner.scanCorpus(directory: lib)) == .pure)
        let suite = root.appendingPathComponent("test/Parse")
        #expect(PackagePurity.forScan(of: suite).universe == ["Build.swift", "Item.swift"])
        #expect(Wiring.verdict("build", in: try FunctionScanner.scanCorpus(directory: suite)) == .refuted)
    }
}
