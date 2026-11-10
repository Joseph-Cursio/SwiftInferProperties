import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

private struct SilentTestDirDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_: String) { /* no-op */ }
}

/// TestLifter M6.0 acceptance bar item (b) — end-to-end confirmation
/// that real CLI invocations get test-side cross-validation when the
/// package root layout matches the conventional `Sources/<target>/`
/// + `Tests/<target>Tests/` shape. Without M6.0, TestLifter scans
/// `Sources/<target>/` and finds no test files; M6.0's walk-up
/// resolver fixes this without requiring the user to pass any flag.
@Suite("Discover — TestLifter cross-validation seam fires under conventional package layout (M6.0)")
struct DiscoverCLITestDirEndToEndTests {

    @Test("Default walk-up: --target Foo finds Tests/FooTests/ via walk-up resolver")
    func defaultWalkUpFindsTests() throws {
        let directory = try makePackageFixture(name: "WalkUpEndToEnd")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try writeSourcesNormalize(in: directory)
        try writeTestsIdempotentBody(in: directory)

        // Mimic the CLI's `--target Foo` resolution: directory =
        // <package-root>/Sources/Foo. With M6.0's walk-up resolver,
        // TestLifter scans <package-root>/Tests/ — finding the
        // matching idempotent test body and lighting up +20.
        let prodTarget = directory.appendingPathComponent("Sources/Foo")
        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: prodTarget,
            diagnostics: SilentTestDirDiagnostics(),
            includePossible: true
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "idempotence" })
        #expect(
            lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 },
            "TestLifter cross-validation seam should fire end-to-end with the M6.0 walk-up resolver"
        )
    }

    @Test("Explicit --test-dir: passing a non-conventional Tests path also works")
    func explicitTestDirEndToEnd() throws {
        let directory = try makePackageFixture(name: "ExplicitEndToEnd")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try writeSourcesNormalize(in: directory)
        // Custom test directory NOT under <root>/Tests/ — only the
        // explicit --test-dir override surfaces these tests.
        let customTests = directory.appendingPathComponent("MyCustomTests")
        try FileManager.default.createDirectory(at: customTests, withIntermediateDirectories: true)
        try idempotenceTestSource().write(
            to: customTests.appendingPathComponent("NormalizerTests.swift"),
            atomically: true,
            encoding: .utf8
        )
        let prodTarget = directory.appendingPathComponent("Sources/Foo")
        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: prodTarget,
            diagnostics: SilentTestDirDiagnostics(),
            includePossible: true,
            explicitTestDirectory: customTests
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "idempotence" })
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
    }

    @Test("Walk-up disabled when no Package.swift: cross-validation does not fire (degraded, not broken)")
    func degradedFallbackNoCrossValidation() throws {
        // No Package.swift in the fixture — walk-up returns nil and
        // the fallback resolver returns the production target. Test
        // files in Tests/ aren't seen by TestLifter, so no cross-
        // validation signal is added. This is the pre-M6.0 behavior
        // (degraded but not broken).
        let directory = try makePackageFixture(name: "DegradedFallback")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesNormalize(in: directory)
        try writeTestsIdempotentBody(in: directory)

        let prodTarget = directory.appendingPathComponent("Sources/Foo")
        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: prodTarget,
            diagnostics: SilentTestDirDiagnostics(),
            includePossible: true
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "idempotence" })
        let hasCrossValidation = lifted.score.signals.contains { $0.kind == .crossValidation }
        #expect(
            !hasCrossValidation,
            "Without Package.swift the walk-up resolver returns the prod target"
        )
    }

    // MARK: - Fixture helpers

    private func makePackageFixture(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscoverCLITestDirE2E-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writePackageManifest(in directory: URL) throws {
        try "// swift-tools-version: 5.9\nimport PackageDescription\n"
            .write(
                to: directory.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8
            )
    }

    private func writeSourcesNormalize(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources/Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public func normalize(_ value: String) -> String {
            return value
        }
        """.write(
            to: sources.appendingPathComponent("Normalizer.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsIdempotentBody(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests/FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try idempotenceTestSource().write(
            to: tests.appendingPathComponent("NormalizerTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func idempotenceTestSource() -> String {
        """
        import XCTest
        @testable import Foo

        final class NormalizerTests: XCTestCase {
            func testIdempotent() {
                let s = "hello"
                let once = normalize(s)
                let twice = normalize(once)
                XCTAssertEqual(once, twice)
            }
        }
        """
    }
}
