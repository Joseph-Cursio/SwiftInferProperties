import Foundation
import Testing
@testable import SwiftInferCLI
@testable import SwiftInferCore

@Suite("DecisionsLoader — explicit path + walk-up implicit lookup + atomic write (M6.1)")
struct DecisionsLoaderTests {

    // MARK: - Read paths

    @Test
    func explicitPathToMissingFileWarns() {
        let result = DecisionsLoader.load(
            startingFrom: URL(fileURLWithPath: "/tmp"),
            explicitPath: URL(fileURLWithPath: "/tmp/does-not-exist.json"),
            fileSystem: NoFilesFileSystem()
        )
        #expect(result.decisions == .empty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("decisions file not found") == true)
    }

    @Test
    func implicitLookupWithoutPackageRootIsSilent() {
        // No Package.swift anywhere → walk-up returns nil →
        // load returns empty without warnings.
        let result = DecisionsLoader.load(
            startingFrom: URL(fileURLWithPath: "/tmp"),
            fileSystem: NoFilesFileSystem()
        )
        #expect(result.decisions == .empty)
        #expect(result.warnings.isEmpty)
        #expect(result.packageRoot == nil)
    }

    @Test
    func implicitLookupWithPackageRootButNoDecisionsFileIsSilent() throws {
        let directory = try makeFixtureDirectory(name: "ImplicitNoDecisions")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let result = DecisionsLoader.load(startingFrom: directory)
        #expect(result.decisions == .empty)
        #expect(result.warnings.isEmpty)
        #expect(result.packageRoot != nil)
    }

    @Test
    func implicitLookupReadsAndDecodesDecisionsFile() throws {
        let directory = try makeFixtureDirectory(name: "ImplicitDecisionsRead")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let decisionsPath = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("decisions.json")
        let canonical = Decisions(records: [
            DecisionRecord(
                identityHash: "DEADBEEF12345678",
                template: "round-trip",
                scoreAtDecision: 90,
                tier: .strong,
                decision: .accepted,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ])
        try DecisionsLoader.write(canonical, to: decisionsPath)

        let result = DecisionsLoader.load(startingFrom: directory)
        #expect(result.decisions == canonical)
        #expect(result.warnings.isEmpty)
    }

    @Test
    func corruptDecisionsFileFallsBackToEmptyAndWarns() throws {
        let directory = try makeFixtureDirectory(name: "CorruptDecisions")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let decisionsDir = directory.appendingPathComponent(".swiftinfer")
        try FileManager.default.createDirectory(at: decisionsDir, withIntermediateDirectories: true)
        try Data("{ this is not valid json".utf8)
            .write(to: decisionsDir.appendingPathComponent("decisions.json"))

        let result = DecisionsLoader.load(startingFrom: directory)
        #expect(result.decisions == .empty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("could not parse decisions") == true)
    }

    @Test
    func explicitPathOverridesImplicitWalkUp() throws {
        // Walk-up would find Package.swift + an implicit decisions
        // file; the --decisions <path> override pulls from elsewhere.
        let directory = try makeFixtureDirectory(name: "ExplicitOverride")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        // Implicit decisions file (would be picked up if no explicit path)
        let implicit = Decisions(records: [
            DecisionRecord(
                identityHash: "AAA1111111111111",
                template: "idempotence",
                scoreAtDecision: 90,
                tier: .strong,
                decision: .skipped,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ])
        try DecisionsLoader.write(
            implicit,
            to: directory
                .appendingPathComponent(".swiftinfer")
                .appendingPathComponent("decisions.json")
        )
        // Explicit override path
        let overridePath = directory.appendingPathComponent("custom-decisions.json")
        let override = Decisions(records: [
            DecisionRecord(
                identityHash: "BBB2222222222222",
                template: "round-trip",
                scoreAtDecision: 70,
                tier: .likely,
                decision: .rejected,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ])
        try DecisionsLoader.write(override, to: overridePath)

        let result = DecisionsLoader.load(startingFrom: directory, explicitPath: overridePath)
        #expect(result.decisions == override)
    }

    @Test
    func newerSchemaVersionLoadsButWarns() throws {
        let directory = try makeFixtureDirectory(name: "NewerSchema")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let decisionsPath = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("decisions.json")
        let futureSchema = Decisions(schemaVersion: 99, records: [])
        try DecisionsLoader.write(futureSchema, to: decisionsPath)

        let result = DecisionsLoader.load(startingFrom: directory)
        #expect(result.decisions.schemaVersion == 99)
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
            .appendingPathComponent("decisions.json")
        let decisions = Decisions(records: [
            DecisionRecord(
                identityHash: "AAA1111111111111",
                template: "idempotence",
                scoreAtDecision: 90,
                tier: .strong,
                decision: .accepted,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ])
        try DecisionsLoader.write(decisions, to: path)
        #expect(FileManager.default.fileExists(atPath: path.path))
    }

    @Test
    func writeRoundTripIsByteIdenticalAcrossReSaves() throws {
        let directory = try makeFixtureDirectory(name: "WriteRoundTrip")
        defer { try? FileManager.default.removeItem(at: directory) }
        // Walk-up needs a Package.swift sentinel to find the implicit
        // .swiftinfer/decisions.json path.
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        let path = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("decisions.json")
        let decisions = Decisions(records: [
            DecisionRecord(
                identityHash: "AAA1111111111111",
                template: "idempotence",
                scoreAtDecision: 90,
                tier: .strong,
                decision: .accepted,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                signalWeights: [
                    SignalSnapshot(kind: "exactNameMatch", weight: 40)
                ]
            )
        ])
        try DecisionsLoader.write(decisions, to: path)
        let firstBytes = try Data(contentsOf: path)
        // Re-read, re-write — must produce identical bytes per the
        // sortedKeys + prettyPrinted + ISO8601 encoder convention.
        let reloaded = DecisionsLoader.load(startingFrom: directory)
        try DecisionsLoader.write(reloaded.decisions, to: path)
        let secondBytes = try Data(contentsOf: path)
        #expect(firstBytes == secondBytes)
    }

    @Test
    func writeOutputUsesSortedKeysForCleanDiffs() throws {
        let directory = try makeFixtureDirectory(name: "WriteSortedKeys")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("decisions.json")
        let decisions = Decisions(records: [
            DecisionRecord(
                identityHash: "AAA1111111111111",
                template: "round-trip",
                scoreAtDecision: 90,
                tier: .strong,
                decision: .accepted,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ])
        try DecisionsLoader.write(decisions, to: path)
        let text = try String(contentsOf: path, encoding: .utf8)
        // sortedKeys puts "decision" before "identityHash" before
        // "scoreAtDecision" before "signalWeights" before "template"
        // before "tier" before "timestamp" — alphabetical order.
        guard let decisionIdx = text.range(of: "\"decision\"")?.lowerBound,
              let identityIdx = text.range(of: "\"identityHash\"")?.lowerBound,
              let templateIdx = text.range(of: "\"template\"")?.lowerBound else {
            Issue.record("Expected fields not found in output")
            return
        }
        #expect(decisionIdx < identityIdx)
        #expect(identityIdx < templateIdx)
    }

    // MARK: - Helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DecisionsLoaderTests-\(name)-\(UUID().uuidString)")
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
