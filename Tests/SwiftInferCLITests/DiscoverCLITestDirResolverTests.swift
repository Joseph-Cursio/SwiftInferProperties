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
            explicitTestDir: testDir
        ) { warnings.append($0) }
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
            explicitTestDir: missing
        ) { warnings.append($0) }
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
            explicitTestDir: nil
        ) { warnings.append($0) }
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
            explicitTestDir: nil
        ) { warnings.append($0) }
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
            explicitTestDir: nil
        ) { warnings.append($0) }
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
