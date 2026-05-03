import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M6.0 acceptance — `--test-dir` CLI override.
/// Tests the `effectiveTestDirectory(productionTarget:explicitTestDir:
/// diagnostic:)` resolver directly + the end-to-end flow where TestLifter's
/// cross-validation seam fires when the test directory is correctly
/// resolved (default walk-up OR explicit override) and silently
/// no-ops when it isn't (the pre-M6.0 broken-but-degraded path).
@Suite("Discover — --test-dir CLI override resolver (M6.0)")
struct DiscoverCLITestDirResolverTests {

    @Test("Explicit --test-dir wins when the path exists")
    func explicitTestDirWins() throws {
        let directory = try makeFixture(name: "ExplicitWins")
        defer { try? FileManager.default.removeItem(at: directory) }
        let prodTarget = directory.appendingPathComponent("Sources/Foo")
        let testDir = directory.appendingPathComponent("CustomTestsDir")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        var warnings: [String] = []
        let resolved = SwiftInferCommand.Discover.effectiveTestDirectory(
            productionTarget: prodTarget,
            explicitTestDir: testDir,
            diagnostic: { warnings.append($0) }
        )
        #expect(resolved.standardizedFileURL == testDir.standardizedFileURL)
        #expect(warnings.isEmpty)
    }

    @Test("Missing --test-dir warns and falls through to walk-up resolution")
    func missingExplicitTestDirWarnsAndFallsThrough() throws {
        let directory = try makeFixture(name: "MissingFallsThrough")
        defer { try? FileManager.default.removeItem(at: directory) }
        let prodTarget = directory.appendingPathComponent("Sources/Foo")
        try writePackageManifest(in: directory)
        let tests = directory.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        let missing = directory.appendingPathComponent("NonExistentTestsDir")

        var warnings: [String] = []
        let resolved = SwiftInferCommand.Discover.effectiveTestDirectory(
            productionTarget: prodTarget,
            explicitTestDir: missing,
            diagnostic: { warnings.append($0) }
        )
        // Walk-up found Package.swift + Tests/ — that's what the
        // resolver returns.
        #expect(resolved.standardizedFileURL == tests.standardizedFileURL)
        #expect(warnings.count == 1)
        #expect(warnings.first?.contains("--test-dir path") == true)
        #expect(warnings.first?.contains("does not exist") == true)
    }

    @Test("Walk-up finds <package-root>/Tests/ when no --test-dir is passed")
    func walkUpFindsPackageRootTests() throws {
        let directory = try makeFixture(name: "WalkUpFinds")
        defer { try? FileManager.default.removeItem(at: directory) }
        let prodTarget = directory.appendingPathComponent("Sources/Foo")
        try writePackageManifest(in: directory)
        let tests = directory.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)

        var warnings: [String] = []
        let resolved = SwiftInferCommand.Discover.effectiveTestDirectory(
            productionTarget: prodTarget,
            explicitTestDir: nil,
            diagnostic: { warnings.append($0) }
        )
        #expect(resolved.standardizedFileURL == tests.standardizedFileURL)
        #expect(warnings.isEmpty)
    }

    @Test("Walk-up falls back to production target when no Package.swift is found")
    func walkUpFallsBackToProductionTarget() throws {
        let directory = try makeFixture(name: "NoPackageSwift")
        defer { try? FileManager.default.removeItem(at: directory) }
        let prodTarget = directory.appendingPathComponent("Sources/Foo")
        try FileManager.default.createDirectory(at: prodTarget, withIntermediateDirectories: true)
        // No Package.swift written — walk-up will hit the filesystem
        // root without finding one. Fallback path returns prodTarget.

        var warnings: [String] = []
        let resolved = SwiftInferCommand.Discover.effectiveTestDirectory(
            productionTarget: prodTarget,
            explicitTestDir: nil,
            diagnostic: { warnings.append($0) }
        )
        #expect(resolved.standardizedFileURL == prodTarget.standardizedFileURL)
        #expect(warnings.isEmpty)
    }

    @Test("Walk-up falls back to production target when Package.swift exists but Tests/ doesn't")
    func walkUpFallsBackWhenTestsMissing() throws {
        let directory = try makeFixture(name: "PackageButNoTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let prodTarget = directory.appendingPathComponent("Sources/Foo")
        try writePackageManifest(in: directory)
        // No Tests/ directory written — walk-up finds Package.swift
        // but the Tests/ check fails. Fallback path returns prodTarget.

        var warnings: [String] = []
        let resolved = SwiftInferCommand.Discover.effectiveTestDirectory(
            productionTarget: prodTarget,
            explicitTestDir: nil,
            diagnostic: { warnings.append($0) }
        )
        #expect(resolved.standardizedFileURL == prodTarget.standardizedFileURL)
        #expect(warnings.isEmpty)
    }

    // MARK: - Fixture helpers

    private func makeFixture(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscoverCLITestDir-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let sources = base.appendingPathComponent("Sources/Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
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
            includePossible: true,
            diagnostics: SilentTestDirDiagnostics()
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
            includePossible: true,
            explicitTestDirectory: customTests,
            diagnostics: SilentTestDirDiagnostics()
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
            includePossible: true,
            diagnostics: SilentTestDirDiagnostics()
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

private struct SilentTestDirDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
