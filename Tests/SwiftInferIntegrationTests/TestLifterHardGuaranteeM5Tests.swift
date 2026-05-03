import Foundation
import SwiftInferTestLifter
import Testing

/// TestLifter M5.6 acceptance bar item (n) — extends the §16 #1 + #2
/// source-tree-immutable guarantees from `TestLifterHardGuaranteeTests`
/// (M1.6 + M2.4 + R1.1.d) to the three M5 detector shapes
/// (monotonicity, count-invariance, reduce-equivalence). A regression
/// in any M5 detector path that wrote back to source would surface
/// here. Split into a sibling suite to keep the original file under
/// SwiftLint's 400-line file-length limit.
@Suite("TestLifter — PRD §16 #1 + #2 source-tree-immutable for M5 detectors (M5.6)")
struct TestLifterHardGuaranteeM5Tests {

    @Test("TestLifter.discover does not modify source files for M5 detector fixtures")
    func sourceTreeStableAfterDiscoverM5() throws {
        let directory = try makeFixtureWithM5Patterns()
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = try snapshot(directory: directory)
        _ = try TestLifter.discover(in: directory)
        let after = try snapshot(directory: directory)
        #expect(before == after, "TestLifter.discover modified the source tree (M5 fixtures)")
    }

    @Test("M5 detector test methods survive discover (PRD §16 #2)")
    func m5MethodsSurviveDiscover() throws {
        let directory = try makeFixtureWithM5Patterns()
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifacts = try TestLifter.discover(in: directory)
        // Three M5 patterns each contribute a lifted suggestion — confirms
        // the lift path actually fired (not just no-op'd over the fixtures).
        #expect(
            artifacts.liftedSuggestions.count >= 3,
            "Fixture should produce at least three lifted suggestions (one per M5 pattern)"
        )

        try assertMethodSurvived(
            directory: directory,
            file: "PricingTests.swift",
            decl: "func testApplyDiscountIsMonotonic()"
        )
        try assertMethodSurvived(
            directory: directory,
            file: "FilterTests.swift",
            decl: "func testFilterPreservesCount()"
        )
        try assertMethodSurvived(
            directory: directory,
            file: "ReducerTests.swift",
            decl: "func testReduceEquivalence()"
        )
    }

    // MARK: - Fixture helpers

    private func makeFixtureWithM5Patterns() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferTestLifterHGM5-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try writeM5DetectorFixtureFiles(in: base)
        return base
    }

    private func writeM5DetectorFixtureFiles(in base: URL) throws {
        try """
        import XCTest

        final class PricingTests: XCTestCase {
            func testApplyDiscountIsMonotonic() {
                let a = 5
                let b = 10
                XCTAssertLessThan(a, b)
                XCTAssertLessThanOrEqual(applyDiscount(a), applyDiscount(b))
            }
        }
        """.write(
            to: base.appendingPathComponent("PricingTests.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        import XCTest

        final class FilterTests: XCTestCase {
            func testFilterPreservesCount() {
                let xs = [1, 2, 3, 4]
                XCTAssertEqual(filter(xs).count, xs.count)
            }
        }
        """.write(
            to: base.appendingPathComponent("FilterTests.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        import XCTest

        final class ReducerTests: XCTestCase {
            func testReduceEquivalence() {
                let items = [1, 2, 3]
                XCTAssertEqual(items.reduce(0, +), items.reversed().reduce(0, +))
            }
        }
        """.write(
            to: base.appendingPathComponent("ReducerTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func assertMethodSurvived(
        directory: URL,
        file: String,
        decl: String
    ) throws {
        let body = try String(
            contentsOf: directory.appendingPathComponent(file),
            encoding: .utf8
        )
        #expect(
            body.contains(decl),
            "TestLifter.discover removed or rewrote the \(decl) declaration in \(file)"
        )
    }

    private func snapshot(directory: URL) throws -> [String: Data] {
        var snap: [String: Data] = [:]
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return snap
        }
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = String(url.path.dropFirst(directory.path.count))
            snap[relative] = try Data(contentsOf: url)
        }
        return snap
    }
}
