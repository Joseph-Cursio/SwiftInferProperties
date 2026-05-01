import Foundation
import Testing
@testable import SwiftInferCLI
@testable import SwiftInferCore

@Suite("BaselineLoader — explicit path + walk-up implicit lookup + atomic write (M6.2)")
struct BaselineLoaderTests {

    // MARK: - Read paths

    @Test
    func explicitPathToMissingFileWarns() {
        let result = BaselineLoader.load(
            startingFrom: URL(fileURLWithPath: "/tmp"),
            explicitPath: URL(fileURLWithPath: "/tmp/does-not-exist.json"),
            fileSystem: NoFilesFileSystem()
        )
        #expect(result.baseline == .empty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("baseline file not found") == true)
    }

    @Test
    func implicitLookupWithoutPackageRootIsSilent() {
        let result = BaselineLoader.load(
            startingFrom: URL(fileURLWithPath: "/tmp"),
            fileSystem: NoFilesFileSystem()
        )
        #expect(result.baseline == .empty)
        #expect(result.warnings.isEmpty)
        #expect(result.packageRoot == nil)
    }

    @Test
    func implicitLookupWithPackageRootButNoBaselineFileIsSilent() throws {
        let directory = try makeFixtureDirectory(name: "ImplicitNoBaseline")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        let result = BaselineLoader.load(startingFrom: directory)
        #expect(result.baseline == .empty)
        #expect(result.warnings.isEmpty)
        #expect(result.packageRoot != nil)
    }

    @Test
    func implicitLookupReadsAndDecodesBaselineFile() throws {
        let directory = try makeFixtureDirectory(name: "ImplicitBaselineRead")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        let baselinePath = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("baseline.json")
        let canonical = Baseline(entries: [
            BaselineEntry(
                identityHash: "DEADBEEF12345678",
                template: "round-trip",
                scoreAtSnapshot: 90,
                tier: .strong
            )
        ])
        try BaselineLoader.write(canonical, to: baselinePath)

        let result = BaselineLoader.load(startingFrom: directory)
        #expect(result.baseline == canonical)
        #expect(result.warnings.isEmpty)
    }

    @Test
    func corruptBaselineFileFallsBackToEmptyAndWarns() throws {
        let directory = try makeFixtureDirectory(name: "CorruptBaseline")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        let dir = directory.appendingPathComponent(".swiftinfer")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ this is not valid json".utf8)
            .write(to: dir.appendingPathComponent("baseline.json"))

        let result = BaselineLoader.load(startingFrom: directory)
        #expect(result.baseline == .empty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("could not parse baseline") == true)
    }

    @Test
    func explicitPathOverridesImplicitWalkUp() throws {
        let directory = try makeFixtureDirectory(name: "ExplicitOverride")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        let implicit = Baseline(entries: [
            BaselineEntry(
                identityHash: "AAA1111111111111",
                template: "idempotence",
                scoreAtSnapshot: 90,
                tier: .strong
            )
        ])
        try BaselineLoader.write(
            implicit,
            to: directory
                .appendingPathComponent(".swiftinfer")
                .appendingPathComponent("baseline.json")
        )
        let overridePath = directory.appendingPathComponent("custom-baseline.json")
        let override = Baseline(entries: [
            BaselineEntry(
                identityHash: "BBB2222222222222",
                template: "round-trip",
                scoreAtSnapshot: 70,
                tier: .likely
            )
        ])
        try BaselineLoader.write(override, to: overridePath)

        let result = BaselineLoader.load(startingFrom: directory, explicitPath: overridePath)
        #expect(result.baseline == override)
    }

    @Test
    func newerSchemaVersionLoadsButWarns() throws {
        let directory = try makeFixtureDirectory(name: "NewerSchema")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        let baselinePath = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("baseline.json")
        let futureSchema = Baseline(schemaVersion: 99, entries: [])
        try BaselineLoader.write(futureSchema, to: baselinePath)

        let result = BaselineLoader.load(startingFrom: directory)
        #expect(result.baseline.schemaVersion == 99)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("schemaVersion 99") == true)
    }

    // MARK: - Write path

    @Test
    func writeCreatesParentDirectory() throws {
        let directory = try makeFixtureDirectory(name: "WriteCreatesDir")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("baseline.json")
        let baseline = Baseline(entries: [
            BaselineEntry(
                identityHash: "AAA1111111111111",
                template: "idempotence",
                scoreAtSnapshot: 90,
                tier: .strong
            )
        ])
        try BaselineLoader.write(baseline, to: path)
        #expect(FileManager.default.fileExists(atPath: path.path))
    }

    @Test
    func writeRoundTripIsByteIdenticalAcrossReSaves() throws {
        let directory = try makeFixtureDirectory(name: "WriteRoundTrip")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        let path = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("baseline.json")
        let baseline = Baseline(entries: [
            BaselineEntry(
                identityHash: "AAA1111111111111",
                template: "idempotence",
                scoreAtSnapshot: 90,
                tier: .strong
            ),
            BaselineEntry(
                identityHash: "BBB2222222222222",
                template: "round-trip",
                scoreAtSnapshot: 70,
                tier: .likely
            )
        ])
        try BaselineLoader.write(baseline, to: path)
        let firstBytes = try Data(contentsOf: path)
        let reloaded = BaselineLoader.load(startingFrom: directory)
        try BaselineLoader.write(reloaded.baseline, to: path)
        let secondBytes = try Data(contentsOf: path)
        #expect(firstBytes == secondBytes)
    }

    // MARK: - Helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("BaselineLoaderTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writePackageManifest(in directory: URL) throws {
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
    }
}

/// Test-only `FileSystemReader` reporting every path as missing.
private struct NoFilesFileSystem: FileSystemReader {
    func fileExists(atPath: String) -> Bool { false }
    func contents(of url: URL) throws -> Data {
        throw NSError(domain: "NoFilesFileSystem", code: 0, userInfo: nil)
    }
}
