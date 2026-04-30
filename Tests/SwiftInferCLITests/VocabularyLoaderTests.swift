import Foundation
import Testing
import SwiftInferCore
@testable import SwiftInferCLI

@Suite("VocabularyLoader — explicit path + walk-up implicit lookup per PRD §4.5")
struct VocabularyLoaderTests {

    // MARK: - Explicit-path mode

    @Test("Explicit path that doesn't exist warns and returns .empty")
    func explicitMissingPathWarns() throws {
        let directory = try makeFixtureDirectory(name: "ExplicitMissing")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("does-not-exist.json")
        let result = VocabularyLoader.load(
            startingFrom: directory,
            explicitPath: path
        )
        #expect(result.vocabulary == .empty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("not found") == true)
        #expect(result.warnings.first?.contains(path.path) == true)
    }

    @Test("Explicit path with malformed JSON warns and returns .empty")
    func explicitMalformedJSONWarns() throws {
        let directory = try makeFixtureDirectory(name: "ExplicitMalformed")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("vocabulary.json")
        try Data("{ malformed:".utf8).write(to: path)
        let result = VocabularyLoader.load(
            startingFrom: directory,
            explicitPath: path
        )
        #expect(result.vocabulary == .empty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("could not parse") == true)
    }

    @Test("Explicit path with valid JSON loads the vocabulary")
    func explicitValidJSONLoads() throws {
        let directory = try makeFixtureDirectory(name: "ExplicitValid")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("vocabulary.json")
        let json = """
        {
          "idempotenceVerbs": ["sanitizeXML"],
          "inversePairs": [["enqueue", "dequeue"]]
        }
        """
        try Data(json.utf8).write(to: path)
        let result = VocabularyLoader.load(
            startingFrom: directory,
            explicitPath: path
        )
        #expect(result.warnings.isEmpty)
        #expect(result.vocabulary.idempotenceVerbs == ["sanitizeXML"])
        #expect(result.vocabulary.inversePairs == [
            InversePair(forward: "enqueue", reverse: "dequeue")
        ])
    }

    // MARK: - Implicit walk-up mode

    @Test("Walk-up finds Package.swift and loads .swiftinfer/vocabulary.json")
    func walkUpFindsPackageRoot() throws {
        let root = try makeFixtureDirectory(name: "WalkUpFinds")
        defer { try? FileManager.default.removeItem(at: root) }
        // Layout:
        //   <root>/Package.swift
        //   <root>/.swiftinfer/vocabulary.json
        //   <root>/Sources/MyTarget/  ← discover starts here
        try writePackageSwift(at: root)
        try writeVocabulary(at: root, json: """
        { "idempotenceVerbs": ["normalizePath"] }
        """)
        let target = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = VocabularyLoader.load(startingFrom: target)
        #expect(result.warnings.isEmpty)
        #expect(result.vocabulary.idempotenceVerbs == ["normalizePath"])
    }

    @Test("Walk-up with no .swiftinfer/vocabulary.json is silent — no warning, .empty")
    func walkUpNoFileIsSilent() throws {
        let root = try makeFixtureDirectory(name: "WalkUpAbsent")
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackageSwift(at: root)
        let target = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = VocabularyLoader.load(startingFrom: target)
        #expect(result.warnings.isEmpty)
        #expect(result.vocabulary == .empty)
    }

    @Test("Walk-up with malformed vocabulary.json warns and returns .empty")
    func walkUpMalformedFileWarns() throws {
        let root = try makeFixtureDirectory(name: "WalkUpMalformed")
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackageSwift(at: root)
        try writeVocabulary(at: root, json: "{ malformed:")
        let target = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = VocabularyLoader.load(startingFrom: target)
        #expect(result.vocabulary == .empty)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("could not parse") == true)
    }

    @Test("Walk-up that never finds Package.swift is silent — no warning, .empty")
    func walkUpNoPackageIsSilent() throws {
        let directory = try makeFixtureDirectory(name: "WalkUpNoPackage")
        defer { try? FileManager.default.removeItem(at: directory) }
        // No Package.swift anywhere in the test directory tree; using a
        // stub FileSystemReader so the walk-up doesn't accidentally hit
        // a real Package.swift higher up the host filesystem.
        let stub = NoPackageStub()
        let result = VocabularyLoader.load(
            startingFrom: directory,
            fileSystem: stub
        )
        #expect(result.warnings.isEmpty)
        #expect(result.vocabulary == .empty)
    }

    // MARK: - Helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabularyLoaderTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writePackageSwift(at root: URL) throws {
        let manifest = root.appendingPathComponent("Package.swift")
        try Data("// swift-tools-version: 6.1\n".utf8).write(to: manifest)
    }

    private func writeVocabulary(at root: URL, json: String) throws {
        let dir = root.appendingPathComponent(".swiftinfer")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("vocabulary.json")
        try Data(json.utf8).write(to: path)
    }
}

/// Stub that pretends every fileExists query returns false. Used to keep
/// the "no Package.swift in walk-up" test independent of whatever's
/// above the temp dir on the host filesystem.
private struct NoPackageStub: FileSystemReader {
    func fileExists(atPath: String) -> Bool { false }
    func contents(of url: URL) throws -> Data { Data() }
}
