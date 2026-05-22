import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

// V1.72.B — disk-resident store: explicit-path + walk-up implicit
// lookup, atomic write, and graceful handling of missing / corrupt
// files. Mirrors VerifyEvidenceStoreTests' shape — the parallel
// store carries the parallel guarantees.

@Suite("PostAcceptanceOutcomesStore — V1.72.B load + write + walk-up")
struct PostAcceptanceOutcomesStoreTests {

    // MARK: - Read paths

    @Test
    func explicitPathToMissingFileWarns() {
        let result = PostAcceptanceOutcomesStore.load(
            startingFrom: URL(fileURLWithPath: "/tmp"),
            explicitPath: URL(fileURLWithPath: "/tmp/does-not-exist.json"),
            fileSystem: NoFilesFileSystem()
        )
        #expect(result.log == .empty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("post-acceptance-outcomes file not found") == true)
    }

    @Test
    func implicitLookupWithoutPackageRootIsSilent() {
        let result = PostAcceptanceOutcomesStore.load(
            startingFrom: URL(fileURLWithPath: "/tmp"),
            fileSystem: NoFilesFileSystem()
        )
        #expect(result.log == .empty)
        #expect(result.warnings.isEmpty)
        #expect(result.packageRoot == nil)
    }

    @Test("implicit lookup with Package.swift but no outcomes file is silent — outcomes are opt-in")
    func implicitLookupWithPackageRootButNoOutcomesFileIsSilent() throws {
        let directory = try makeFixtureDirectory(name: "ImplicitNoOutcomes")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let result = PostAcceptanceOutcomesStore.load(startingFrom: directory)
        #expect(result.log == .empty)
        #expect(result.warnings.isEmpty)
        #expect(result.packageRoot != nil)
    }

    @Test
    func implicitLookupReadsAndDecodesOutcomesFile() throws {
        let directory = try makeFixtureDirectory(name: "ImplicitOutcomesRead")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let outcomesPath = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("post-acceptance-outcomes.json")
        let canonical = PostAcceptanceOutcomeLog(records: [
            PostAcceptanceOutcome(
                identityHash: "DEADBEEF12345678",
                template: "round-trip",
                outcome: .stillPasses,
                detail: "bothPass",
                originalAcceptedAt: Date(timeIntervalSince1970: 1_700_000_000),
                checkedAt: Date(timeIntervalSince1970: 1_700_001_000),
                swiftInferVersion: "1.72.0"
            )
        ])
        try PostAcceptanceOutcomesStore.write(canonical, to: outcomesPath)

        let result = PostAcceptanceOutcomesStore.load(startingFrom: directory)
        #expect(result.log == canonical)
        #expect(result.warnings.isEmpty)
    }

    @Test
    func corruptOutcomesFileFallsBackToEmptyAndWarns() throws {
        let directory = try makeFixtureDirectory(name: "CorruptOutcomes")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let outcomesDir = directory.appendingPathComponent(".swiftinfer")
        try FileManager.default.createDirectory(at: outcomesDir, withIntermediateDirectories: true)
        try Data("{ not valid json".utf8)
            .write(to: outcomesDir.appendingPathComponent("post-acceptance-outcomes.json"))

        let result = PostAcceptanceOutcomesStore.load(startingFrom: directory)
        #expect(result.log == .empty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("could not parse post-acceptance-outcomes") == true)
    }

    @Test("newer-schema file warns but still returns the parsed log")
    func newerSchemaVersionWarns() throws {
        let directory = try makeFixtureDirectory(name: "NewerSchema")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let outcomesPath = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("post-acceptance-outcomes.json")
        let future = PostAcceptanceOutcomeLog(schemaVersion: 999, records: [])
        try PostAcceptanceOutcomesStore.write(future, to: outcomesPath)

        let result = PostAcceptanceOutcomesStore.load(startingFrom: directory)
        #expect(result.log == future)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("schemaVersion 999 is newer") == true)
    }

    // MARK: - Write path

    @Test("write creates the .swiftinfer parent directory chain when missing")
    func writeCreatesParentDirectoryChain() throws {
        let directory = try makeFixtureDirectory(name: "WriteCreatesParent")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outcomesPath = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("post-acceptance-outcomes.json")
        // Parent doesn't exist yet — the write must mkdir.
        try PostAcceptanceOutcomesStore.write(.empty, to: outcomesPath)
        #expect(FileManager.default.fileExists(atPath: outcomesPath.path))
    }

    @Test("write produces sortedKeys + prettyPrinted JSON for stable diffs")
    func writeIsStable() throws {
        let directory = try makeFixtureDirectory(name: "WriteStable")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outcomesPath = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("post-acceptance-outcomes.json")
        let log = PostAcceptanceOutcomeLog(records: [
            PostAcceptanceOutcome(
                identityHash: "AAA1111111111111",
                template: "round-trip",
                outcome: .stillPasses,
                detail: "bothPass",
                originalAcceptedAt: Date(timeIntervalSince1970: 1_700_000_000),
                checkedAt: Date(timeIntervalSince1970: 1_700_001_000),
                swiftInferVersion: "1.72.0"
            )
        ])
        try PostAcceptanceOutcomesStore.write(log, to: outcomesPath)
        let raw = try String(contentsOf: outcomesPath, encoding: .utf8)
        // sortedKeys → "checkedAt" comes before "detail" comes before "identityHash" alphabetically.
        let checkedAtIdx = raw.range(of: "checkedAt")!.lowerBound
        let detailIdx = raw.range(of: "detail")!.lowerBound
        let identityIdx = raw.range(of: "identityHash")!.lowerBound
        #expect(checkedAtIdx < detailIdx)
        #expect(detailIdx < identityIdx)
    }

    // MARK: - Helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("PostAcceptanceOutcomesStoreTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}

/// Test-only `FileSystemReader` reporting every path as missing.
private struct NoFilesFileSystem: FileSystemReader {
    func fileExists(atPath _: String) -> Bool { false }
    func contents(of _: URL) throws -> Data {
        throw NSError(domain: "NoFilesFileSystem", code: 0, userInfo: nil)
    }
}
