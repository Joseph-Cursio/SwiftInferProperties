import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

@Suite("VerifyEvidenceStore — explicit path + walk-up implicit lookup + atomic write (V1.64.A)")
struct VerifyEvidenceStoreTests {

    // MARK: - Read paths

    @Test
    func explicitPathToMissingFileWarns() {
        let result = VerifyEvidenceStore.load(
            startingFrom: URL(fileURLWithPath: "/tmp"),
            explicitPath: URL(fileURLWithPath: "/tmp/does-not-exist.json"),
            fileSystem: NoFilesFileSystem()
        )
        #expect(result.log == .empty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("verify-evidence file not found") == true)
    }

    @Test
    func implicitLookupWithoutPackageRootIsSilent() {
        let result = VerifyEvidenceStore.load(
            startingFrom: URL(fileURLWithPath: "/tmp"),
            fileSystem: NoFilesFileSystem()
        )
        #expect(result.log == .empty)
        #expect(result.warnings.isEmpty)
        #expect(result.packageRoot == nil)
    }

    @Test
    func implicitLookupWithPackageRootButNoEvidenceFileIsSilent() throws {
        let directory = try makeFixtureDirectory(name: "ImplicitNoEvidence")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let result = VerifyEvidenceStore.load(startingFrom: directory)
        #expect(result.log == .empty)
        #expect(result.warnings.isEmpty)
        #expect(result.packageRoot != nil)
    }

    @Test
    func implicitLookupReadsAndDecodesEvidenceFile() throws {
        let directory = try makeFixtureDirectory(name: "ImplicitEvidenceRead")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let evidencePath = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("verify-evidence.json")
        let canonical = VerifyEvidenceLog(records: [
            VerifyEvidence(
                identityHash: "DEADBEEF12345678",
                template: "round-trip",
                outcome: .measuredBothPass,
                detail: "defaultTrials=100 edgeTrials=100 edgeSampled=6",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.64.0"
            )
        ])
        try VerifyEvidenceStore.write(canonical, to: evidencePath)

        let result = VerifyEvidenceStore.load(startingFrom: directory)
        #expect(result.log == canonical)
        #expect(result.warnings.isEmpty)
    }

    @Test
    func corruptEvidenceFileFallsBackToEmptyAndWarns() throws {
        let directory = try makeFixtureDirectory(name: "CorruptEvidence")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let evidenceDir = directory.appendingPathComponent(".swiftinfer")
        try FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)
        try Data("{ this is not valid json".utf8)
            .write(to: evidenceDir.appendingPathComponent("verify-evidence.json"))

        let result = VerifyEvidenceStore.load(startingFrom: directory)
        #expect(result.log == .empty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("could not parse verify-evidence") == true)
    }

    @Test
    func explicitPathOverridesImplicitWalkUp() throws {
        let directory = try makeFixtureDirectory(name: "ExplicitOverride")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let implicit = VerifyEvidenceLog(records: [
            VerifyEvidence(
                identityHash: "AAA1111111111111",
                template: "idempotence",
                outcome: .measuredDefaultFails,
                detail: "trial=3",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.64.0"
            )
        ])
        try VerifyEvidenceStore.write(
            implicit,
            to: directory
                .appendingPathComponent(".swiftinfer")
                .appendingPathComponent("verify-evidence.json")
        )
        let overridePath = directory.appendingPathComponent("custom-evidence.json")
        let override = VerifyEvidenceLog(records: [
            VerifyEvidence(
                identityHash: "BBB2222222222222",
                template: "round-trip",
                outcome: .measuredBothPass,
                detail: nil,
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.64.0"
            )
        ])
        try VerifyEvidenceStore.write(override, to: overridePath)

        let result = VerifyEvidenceStore.load(startingFrom: directory, explicitPath: overridePath)
        #expect(result.log == override)
    }

    @Test
    func newerSchemaVersionLoadsButWarns() throws {
        let directory = try makeFixtureDirectory(name: "NewerSchema")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let evidencePath = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("verify-evidence.json")
        let futureSchema = VerifyEvidenceLog(schemaVersion: 99, records: [])
        try VerifyEvidenceStore.write(futureSchema, to: evidencePath)

        let result = VerifyEvidenceStore.load(startingFrom: directory)
        #expect(result.log.schemaVersion == 99)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("schemaVersion 99") == true)
    }

    // MARK: - Write path

    @Test
    func writeCreatesParentDirectoryAtomically() throws {
        let directory = try makeFixtureDirectory(name: "WriteCreatesDir")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("verify-evidence.json")
        let log = VerifyEvidenceLog(records: [
            VerifyEvidence(
                identityHash: "AAA1111111111111",
                template: "idempotence",
                outcome: .measuredBothPass,
                detail: "defaultTrials=100 edgeTrials=0 edgeSampled=0",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.64.0"
            )
        ])
        try VerifyEvidenceStore.write(log, to: path)
        #expect(FileManager.default.fileExists(atPath: path.path))
    }

    @Test
    func writeRoundTripIsByteIdenticalAcrossReSaves() throws {
        let directory = try makeFixtureDirectory(name: "WriteRoundTrip")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("verify-evidence.json")
        let log = VerifyEvidenceLog(records: [
            VerifyEvidence(
                identityHash: "AAA1111111111111",
                template: "round-trip",
                outcome: .measuredBothPass,
                detail: "defaultTrials=100 edgeTrials=100 edgeSampled=6",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.64.0"
            )
        ])
        try VerifyEvidenceStore.write(log, to: path)
        let firstBytes = try Data(contentsOf: path)
        try VerifyEvidenceStore.write(log, to: path)
        let secondBytes = try Data(contentsOf: path)
        #expect(firstBytes == secondBytes)
    }

    @Test
    func writeProducesSortedKeyOrdering() throws {
        let directory = try makeFixtureDirectory(name: "SortedKeys")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("verify-evidence.json")
        let log = VerifyEvidenceLog(records: [
            VerifyEvidence(
                identityHash: "AAA1111111111111",
                template: "round-trip",
                outcome: .measuredBothPass,
                detail: "defaultTrials=100 edgeTrials=0 edgeSampled=0",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.64.0"
            )
        ])
        try VerifyEvidenceStore.write(log, to: path)
        let text = try String(contentsOf: path, encoding: .utf8)
        // sortedKeys → alphabetical: capturedAt < detail < identityHash
        // < outcome < swiftInferVersion < template.
        guard let capturedIdx = text.range(of: "\"capturedAt\"")?.lowerBound,
              let identityIdx = text.range(of: "\"identityHash\"")?.lowerBound,
              let templateIdx = text.range(of: "\"template\"")?.lowerBound else {
            Issue.record("Expected fields not found in output")
            return
        }
        #expect(capturedIdx < identityIdx)
        #expect(identityIdx < templateIdx)
    }

    // MARK: - Helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("VerifyEvidenceStoreTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}

/// Test-only `FileSystemReader` reporting every path as missing. Used
/// to drive the "no walk-up target found" code path without setting up
/// a real fixture tree.
private struct NoFilesFileSystem: FileSystemReader {
    func fileExists(atPath: String) -> Bool { false }
    func contents(of url: URL) throws -> Data {
        throw NSError(domain: "NoFilesFileSystem", code: 0, userInfo: nil)
    }
}
