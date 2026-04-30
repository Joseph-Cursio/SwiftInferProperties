import Foundation
import Testing
import SwiftInferCore
@testable import SwiftInferCLI

@Suite("ConfigLoader — explicit path + walk-up implicit lookup per PRD §5.8 (M2)")
struct ConfigLoaderTests {

    // MARK: - Explicit-path mode

    @Test("Explicit path that doesn't exist warns and returns defaults")
    func explicitMissingPathWarns() throws {
        let directory = try makeFixtureDirectory(name: "ExplicitMissing")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("does-not-exist.toml")
        let result = ConfigLoader.load(startingFrom: directory, explicitPath: path)
        #expect(result.config == .defaults)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("not found") == true)
    }

    @Test("Explicit path with malformed TOML warns and returns defaults")
    func explicitMalformedWarns() throws {
        let directory = try makeFixtureDirectory(name: "ExplicitMalformed")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("config.toml")
        try Data("[discover\nflag = true".utf8).write(to: path)
        let result = ConfigLoader.load(startingFrom: directory, explicitPath: path)
        #expect(result.config == .defaults)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("could not parse") == true)
    }

    @Test("Explicit path with valid TOML loads both knobs")
    func explicitValidLoads() throws {
        let directory = try makeFixtureDirectory(name: "ExplicitValid")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("config.toml")
        try Data("""
        [discover]
        includePossible = true
        vocabularyPath = "vocab.json"
        """.utf8).write(to: path)
        let result = ConfigLoader.load(startingFrom: directory, explicitPath: path)
        #expect(result.warnings.isEmpty)
        #expect(result.config.includePossible == true)
        #expect(result.config.vocabularyPath == "vocab.json")
    }

    // MARK: - Implicit walk-up mode

    @Test("Walk-up finds Package.swift and loads .swiftinfer/config.toml")
    func walkUpFindsConfig() throws {
        let root = try makeFixtureDirectory(name: "WalkUpFinds")
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackageSwift(at: root)
        try writeConfig(at: root, contents: """
        [discover]
        includePossible = true
        """)
        let target = root.appendingPathComponent("Sources/MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = ConfigLoader.load(startingFrom: target)
        #expect(result.warnings.isEmpty)
        #expect(result.config.includePossible == true)
        #expect(result.packageRoot?.path == root.standardizedFileURL.path)
    }

    @Test("Walk-up with no .swiftinfer/config.toml is silent — defaults, no warnings")
    func walkUpNoFileIsSilent() throws {
        let root = try makeFixtureDirectory(name: "WalkUpAbsent")
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackageSwift(at: root)
        let target = root.appendingPathComponent("Sources/MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = ConfigLoader.load(startingFrom: target)
        #expect(result.warnings.isEmpty)
        #expect(result.config == .defaults)
        #expect(result.packageRoot?.path == root.standardizedFileURL.path)
    }

    @Test("Walk-up with malformed config warns and falls back to defaults")
    func walkUpMalformedWarns() throws {
        let root = try makeFixtureDirectory(name: "WalkUpMalformed")
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackageSwift(at: root)
        try writeConfig(at: root, contents: "[discover\nbroken")
        let target = root.appendingPathComponent("Sources/MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = ConfigLoader.load(startingFrom: target)
        #expect(result.config == .defaults)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("could not parse") == true)
    }

    @Test("Walk-up that never finds Package.swift is silent — defaults, no warnings, nil packageRoot")
    func walkUpNoPackageIsSilent() throws {
        let directory = try makeFixtureDirectory(name: "WalkUpNoPackage")
        defer { try? FileManager.default.removeItem(at: directory) }
        let stub = NoPackageStub()
        let result = ConfigLoader.load(startingFrom: directory, fileSystem: stub)
        #expect(result.warnings.isEmpty)
        #expect(result.config == .defaults)
        #expect(result.packageRoot == nil)
    }

    // MARK: - Decoding

    @Test("Unknown sections are silently ignored to leave room for M3+ knobs")
    func unknownSectionIgnored() throws {
        let directory = try makeFixtureDirectory(name: "UnknownSection")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("config.toml")
        try Data("""
        [discover]
        includePossible = true

        [futureSectionM3]
        someKnob = "v"
        """.utf8).write(to: path)
        let result = ConfigLoader.load(startingFrom: directory, explicitPath: path)
        #expect(result.warnings.isEmpty)
        #expect(result.config.includePossible == true)
    }

    @Test("Unknown keys inside [discover] are silently ignored")
    func unknownKeyIgnored() throws {
        let directory = try makeFixtureDirectory(name: "UnknownKey")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("config.toml")
        try Data("""
        [discover]
        includePossible = true
        someFutureKnob = "v"
        """.utf8).write(to: path)
        let result = ConfigLoader.load(startingFrom: directory, explicitPath: path)
        #expect(result.warnings.isEmpty)
        #expect(result.config.includePossible == true)
    }

    @Test("Wrong type for a known key warns and that key falls back to default")
    func wrongTypeForKnownKeyWarns() throws {
        let directory = try makeFixtureDirectory(name: "WrongType")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("config.toml")
        try Data("""
        [discover]
        includePossible = "should-be-bool"
        vocabularyPath = "vocab.json"
        """.utf8).write(to: path)
        let result = ConfigLoader.load(startingFrom: directory, explicitPath: path)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("expected boolean") == true)
        // Wrong-typed key falls back; right-typed key still loads.
        #expect(result.config.includePossible == false)
        #expect(result.config.vocabularyPath == "vocab.json")
    }

    // MARK: - Helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigLoaderTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writePackageSwift(at root: URL) throws {
        let manifest = root.appendingPathComponent("Package.swift")
        try Data("// swift-tools-version: 6.1\n".utf8).write(to: manifest)
    }

    private func writeConfig(at root: URL, contents: String) throws {
        let dir = root.appendingPathComponent(".swiftinfer")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("config.toml")
        try Data(contents.utf8).write(to: path)
    }
}

private struct NoPackageStub: FileSystemReader {
    func fileExists(atPath: String) -> Bool { false }
    func contents(of url: URL) throws -> Data { Data() }
}
