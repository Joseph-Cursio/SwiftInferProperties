import Foundation
import SwiftInferTestLifter
import Testing

/// `TestSuiteParser.scanTests(directories:)` — the multi-root scan behind
/// test-target scoping (`TestTargetScope`).
///
/// Scoping turns TestLifter's single `Tests/` root into a **set** of sibling roots,
/// one per test target that could be exercising the scanned module. Two properties
/// of that widening are load-bearing and neither is obvious from the happy path.
@Suite("TestLifter — multi-root scanning is deduplicated and order-stable")
struct MultiRootScanTests {

    private static func makeTree() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiRootScan-\(UUID().uuidString)")
        let fileManager = FileManager.default
        for suite in ["AlphaTests", "BetaTests"] {
            let directory = base.appendingPathComponent("Tests/\(suite)")
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try """
            import Testing

            @Suite struct \(suite) {
                @Test func roundTrips() {
                    let value = 7
                    #expect(decode(encode(value)) == value)
                }
            }
            """.write(
                to: directory.appendingPathComponent("\(suite).swift"),
                atomically: true,
                encoding: .utf8
            )
        }
        return base
    }

    /// **Overlapping roots must not double-count.** Scoping can hand back a root and
    /// an ancestor of it (a manifest `path` pointing at `Tests/` itself alongside a
    /// conventional `Tests/FooTests`). Parsing a file twice produces two identical
    /// `TestMethodSummary` records, and downstream that reads as *independent
    /// corroboration* — the "stated N times by the scan" line — inflating a score
    /// from a single source. The nesting filter is what stops it.
    @Test("a root nested inside another is not scanned twice")
    func nestedRootsAreNotDoubleCounted() throws {
        let base = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: base) }
        let tests = base.appendingPathComponent("Tests")

        let wholeTree = try TestSuiteParser.scanTests(directories: [tests])
        let withNested = try TestSuiteParser.scanTests(
            directories: [tests, tests.appendingPathComponent("AlphaTests")]
        )
        #expect(withNested.count == wholeTree.count)
        #expect(!wholeTree.isEmpty, "fixture produced no summaries, so this proves nothing")
    }

    /// A root repeated verbatim is likewise scanned once.
    @Test("a repeated root is scanned once")
    func repeatedRootIsScannedOnce() throws {
        let base = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: base) }
        let alpha = base.appendingPathComponent("Tests/AlphaTests")
        let once = try TestSuiteParser.scanTests(directories: [alpha])
        let twice = try TestSuiteParser.scanTests(directories: [alpha, alpha])
        #expect(once.count == twice.count)
        #expect(!once.isEmpty)
    }

    /// **Root order must not change the output.** PRD §16 #6 promises byte-identical
    /// reproducibility, and the scoped root set arrives from a dictionary walk over
    /// the manifest, whose order is not guaranteed. Sorting the roots is what makes
    /// the concatenation stable; without it the same package could lift the same
    /// laws in a different order run to run.
    @Test("root order does not change the scan result")
    func rootOrderIsIrrelevant() throws {
        let base = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: base) }
        let alpha = base.appendingPathComponent("Tests/AlphaTests")
        let beta = base.appendingPathComponent("Tests/BetaTests")

        let forward = try TestSuiteParser.scanTests(directories: [alpha, beta])
        let reversed = try TestSuiteParser.scanTests(directories: [beta, alpha])
        #expect(forward.map(\.methodName) == reversed.map(\.methodName))
        #expect(!forward.isEmpty)
    }

    /// **An empty root set lifts nothing, and that is an answer.** It is what a
    /// production target no test target reaches must produce; folding it into "scan
    /// everything" is precisely the defect the scoping fix closes.
    @Test("an empty root set yields no summaries")
    func emptyRootSetYieldsNothing() throws {
        #expect(try TestSuiteParser.scanTests(directories: []).isEmpty)
    }

    /// The singular entry point still behaves exactly as before — it is now a
    /// one-element call into the plural form, and every existing caller depends on
    /// that being a pure refactor.
    @Test("the singular scanTests still agrees with the plural form")
    func singularAgreesWithPlural() throws {
        let base = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: base) }
        let tests = base.appendingPathComponent("Tests")
        let singular = try TestSuiteParser.scanTests(directory: tests)
        let plural = try TestSuiteParser.scanTests(directories: [tests])
        #expect(singular.map(\.methodName) == plural.map(\.methodName))
        #expect(!singular.isEmpty)
    }
}
