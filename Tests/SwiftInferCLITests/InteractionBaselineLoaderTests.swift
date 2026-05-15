import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V2.0 M10 — InteractionBaselineLoader (explicit path / implicit
// walk-up / write round-trip). Mirrors v1's BaselineLoader test
// posture.

@Suite("InteractionBaselineLoader — V2.0 M10 disk I/O")
struct InteractionBaselineLoaderTests {

    private func tempPackageRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InteractionBaselineLoaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Place an empty Package.swift so walk-up resolves here.
        try Data("// generated".utf8).write(
            to: root.appendingPathComponent("Package.swift")
        )
        return root
    }

    private func sampleEntry(identity: String = "DEADBEEFCAFEFACE") -> InteractionBaselineEntry {
        InteractionBaselineEntry(
            identityHash: identity,
            family: .cardinality,
            scoreAtSnapshot: 80,
            tier: .strong,
            reducerQualifiedName: "Inbox.body"
        )
    }

    // MARK: - Implicit walk-up

    @Test("implicit load: walks up to Package.swift, reads .swiftinfer/interaction-baseline.json")
    func implicitWalkUpLoadsExistingFile() throws {
        let root = try tempPackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let baseline = InteractionBaseline(entries: [sampleEntry()])
        try InteractionBaselineLoader.write(
            baseline,
            to: InteractionBaselineLoader.defaultPath(for: root)
        )
        let sources = root.appendingPathComponent("Sources").appendingPathComponent("MyApp")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let result = InteractionBaselineLoader.load(startingFrom: sources)
        #expect(result.baseline == baseline)
        #expect(result.warnings.isEmpty)
        #expect(result.packageRoot?.standardizedFileURL == root.standardizedFileURL)
    }

    @Test("implicit load: missing file is silent (no warnings, empty baseline)")
    func implicitMissingFileIsSilent() throws {
        let root = try tempPackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = InteractionBaselineLoader.load(startingFrom: root)
        #expect(result.baseline == .empty)
        #expect(result.warnings.isEmpty)
        #expect(result.packageRoot != nil)
    }

    // MARK: - Explicit override

    @Test("explicit path: reads from the supplied URL even outside the package root")
    func explicitPathOverridesWalkUp() throws {
        let root = try tempPackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let externalPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ext-baseline-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: externalPath) }
        let baseline = InteractionBaseline(entries: [sampleEntry(identity: "EXTERNAL00000000")])
        try InteractionBaselineLoader.write(baseline, to: externalPath)
        let result = InteractionBaselineLoader.load(
            startingFrom: root,
            explicitPath: externalPath
        )
        #expect(result.baseline == baseline)
        #expect(result.warnings.isEmpty)
    }

    @Test("explicit path: missing file warns and returns empty baseline")
    func explicitMissingFileWarns() {
        let nowhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID()).json")
        let result = InteractionBaselineLoader.load(
            startingFrom: FileManager.default.temporaryDirectory,
            explicitPath: nowhere
        )
        #expect(result.baseline == .empty)
        #expect(result.warnings.contains { $0.contains("interaction-baseline file not found") })
    }

    // MARK: - Write round-trip

    @Test("write atomically creates the parent directory chain")
    func writeCreatesParentDirectory() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline-write-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let path = scratch.appendingPathComponent(".swiftinfer/interaction-baseline.json")
        let baseline = InteractionBaseline(entries: [sampleEntry()])
        try InteractionBaselineLoader.write(baseline, to: path)
        #expect(FileManager.default.fileExists(atPath: path.path))
    }

    @Test("write output is byte-stable across re-saves (sortedKeys + prettyPrinted)")
    func writeOutputIsByteStable() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline-stable-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let path = scratch.appendingPathComponent(".swiftinfer/interaction-baseline.json")
        let baseline = InteractionBaseline(entries: [sampleEntry()])
        try InteractionBaselineLoader.write(baseline, to: path)
        let first = try Data(contentsOf: path)
        try InteractionBaselineLoader.write(baseline, to: path)
        let second = try Data(contentsOf: path)
        #expect(first == second)
    }

    // MARK: - Malformed file

    @Test("malformed JSON warns and returns empty baseline")
    func malformedJSONWarns() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline-malformed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let path = scratch.appendingPathComponent("baseline.json")
        try Data("not json".utf8).write(to: path)
        let result = InteractionBaselineLoader.load(
            startingFrom: scratch,
            explicitPath: path
        )
        #expect(result.baseline == .empty)
        #expect(result.warnings.contains { $0.contains("could not parse interaction-baseline") })
    }
}
