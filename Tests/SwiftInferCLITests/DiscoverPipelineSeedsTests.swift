import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

@Suite("Discover pipeline — --seeds focus (lint → infer pipeline consumer)")
struct DiscoverPipelineSeedsTests {

    /// Two Strong idempotent functions in one file. Seeding one focuses the
    /// output to exactly that suggestion; the other is dropped.
    private static let twoCandidates = """
    struct Sanitizer {
        func normalize(_ value: String) -> String {
            return normalize(normalize(value))
        }
        func sanitize(_ value: String) -> String {
            return sanitize(sanitize(value))
        }
    }
    """

    @Test("No manifest surfaces every suggestion (control)")
    func noManifestSurfacesAll() throws {
        let directory = try writeDPFixture(name: "SeedsControl", contents: Self.twoCandidates)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(directory: directory, includePossible: false, output: recording)
        #expect(recording.text.contains("2 suggestions."))
        #expect(recording.text.contains("normalize(_:)"))
        #expect(recording.text.contains("sanitize(_:)"))
    }

    @Test("A manifest focuses output to the seeded function only")
    func manifestFocusesToSeededFunction() throws {
        let directory = try writeDPFixture(name: "SeedsFocus", contents: Self.twoCandidates)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = SeedManifest(seeds: [
            .init(file: "Source.swift", line: 2, symbol: "normalize", rule: "Pure Function Property-Test Candidate")
        ])
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text.contains("1 suggestion."))
        #expect(recording.text.contains("normalize(_:)"))
        #expect(recording.text.contains("sanitize(_:)") == false)
        #expect(diagnostics.lines.contains { $0.contains("focused on 1 seed(s): kept 1 of 2 suggestion(s)") })
    }

    @Test("Seeding by a different filename (basename mismatch) focuses to nothing")
    func basenameMismatchFocusesToNothing() throws {
        let directory = try writeDPFixture(name: "SeedsMismatch", contents: Self.twoCandidates)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = SeedManifest(seeds: [.init(file: "Other.swift", line: 2, symbol: "normalize")])
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording
        )
        #expect(recording.text == "0 suggestions.")
    }

    @Test("An empty manifest applies no focus rather than discarding everything")
    func emptyManifestAppliesNoFocus() throws {
        // This used to assert `"0 suggestions."`, on the reading that "focus on these zero
        // functions" means "keep zero suggestions". Defensible for a manifest someone sat down and
        // wrote. But nobody writes this manifest — it is whatever the producing linter found, and a
        // linter with a blind spot emits an empty one. The filter then threw away every genuine
        // suggestion and reported a confident zero, which made running the documented lint → infer
        // pipeline *strictly worse* than running swift-infer alone.
        //
        // Focusing on nothing is not a request anyone makes. It is what a producer that found
        // nothing looks like, and the honest answer is to say so and not filter.
        let directory = try writeDPFixture(name: "SeedsEmpty", contents: Self.twoCandidates)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: SeedManifest(seeds: []),
            output: recording,
            diagnostics: diagnostics
        )

        #expect(recording.text.contains("2 suggestions."))
        #expect(diagnostics.joined.contains("warning"))
    }

    @Test("An off-version manifest is consumed best-effort with a warning")
    func offVersionWarnsButConsumes() throws {
        let directory = try writeDPFixture(name: "SeedsVersion", contents: Self.twoCandidates)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = SeedManifest(version: 99, seeds: [.init(file: "Source.swift", line: 2, symbol: "normalize")])
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text.contains("1 suggestion."))
        #expect(diagnostics.lines.contains { $0.contains("version 99 is not the supported version 1") })
    }

    // MARK: - Generic laws (broaden discover: seeded pure fn → determinism)

    @Test("Synthesizes a determinism law for a seeded function no template matched")
    func synthesizesDeterminismForUncoveredSeed() throws {
        let directory = try writeDPFixture(name: "GenericLaw", contents: """
        func describe(_ n: Int, prefix: String) -> String { prefix + "\\(n)" }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = SeedManifest(seeds: [.init(file: "Source.swift", line: 1, symbol: "describe")])
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text.contains("Template: determinism"))
        #expect(recording.text.contains("describe(_:prefix:)"))
        #expect(recording.text.contains("f(x) == f(x)"))
        #expect(diagnostics.lines.contains { $0.contains("synthesized 1 generic determinism law") })
    }

    @Test("Skips the determinism law when a template already covers the seeded function")
    func skipsDeterminismWhenTemplateCovers() throws {
        let directory = try writeDPFixture(name: "GenericCovered", contents: """
        func normalize(_ value: String) -> String { normalize(normalize(value)) }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = SeedManifest(seeds: [.init(file: "Source.swift", line: 1, symbol: "normalize")])
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording
        )
        #expect(recording.text.contains("Template: idempotence"))
        #expect(recording.text.contains("Template: determinism") == false)
    }

    @Test("Determinism requires a total, free/static, value-returning function")
    func determinismQualificationFilters() throws {
        let directory = try writeDPFixture(name: "GenericQualify", contents: """
        func risky(_ s: String) throws -> Int { Int(s) ?? 0 }
        struct Box { func get(_ key: String) -> Int { 0 } }
        func noParams() -> Int { 0 }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = SeedManifest(seeds: [
            .init(file: "Source.swift", line: 1, symbol: "risky"),
            .init(file: "Source.swift", line: 2, symbol: "get"),
            .init(file: "Source.swift", line: 3, symbol: "noParams")
        ])
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording
        )
        // Throwing, instance-method, and no-parameter functions are all excluded.
        #expect(recording.text.contains("Template: determinism") == false)
    }

    @Test("No determinism laws without a seed manifest")
    func noDeterminismWithoutSeeds() throws {
        let directory = try writeDPFixture(name: "GenericNoSeeds", contents: """
        func describe(_ n: Int, prefix: String) -> String { prefix + "\\(n)" }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(directory: directory, includePossible: false, output: recording)
        #expect(recording.text.contains("Template: determinism") == false)
    }

    // MARK: - loadSeedManifest

    @Test("loadSeedManifest decodes a producer-shaped manifest")
    func loadsProducerShapedManifest() throws {
        let directory = try makeDPFixtureDirectory(name: "SeedsLoad")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("seeds.json")
        try Data("""
        { "version": 1, "seeds": [
            { "file": "Math.swift", "line": 3, "symbol": "add", "rule": "Pure Function Property-Test Candidate" }
        ] }
        """.utf8).write(to: path)
        let manifest = try SwiftInferCommand.Discover.loadSeedManifest(at: path)
        #expect(manifest.version == 1)
        #expect(manifest.seeds.count == 1)
        #expect(manifest.seeds.first?.symbol == "add")
        #expect(manifest.seeds.first?.file == "Math.swift")
    }

    @Test("loadSeedManifest throws on a missing file")
    func throwsOnMissingFile() throws {
        let directory = try makeDPFixtureDirectory(name: "SeedsMissing")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("nope.json")
        #expect(throws: (any Error).self) {
            _ = try SwiftInferCommand.Discover.loadSeedManifest(at: path)
        }
    }

    @Test("loadSeedManifest throws on malformed JSON")
    func throwsOnMalformedJSON() throws {
        let directory = try makeDPFixtureDirectory(name: "SeedsMalformed")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("seeds.json")
        try Data("{ not json".utf8).write(to: path)
        #expect(throws: (any Error).self) {
            _ = try SwiftInferCommand.Discover.loadSeedManifest(at: path)
        }
    }
}
