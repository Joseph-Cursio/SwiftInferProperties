import Foundation
import Testing
@testable import SwiftInferCLI

@Suite("Discover pipeline — end-to-end against on-disk fixtures")
struct DiscoverPipelineTests {

    @Test("Empty target directory renders the zero-suggestions sentinel")
    func emptyTargetRendersSentinel() throws {
        let directory = try makeFixtureDirectory(name: "EmptyTarget")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )
        #expect(recording.text == "0 suggestions.")
    }

    @Test("Possible-tier suggestions are hidden by default")
    func possibleTierHiddenByDefault() throws {
        let directory = try writeFixture(name: "HiddenPossible", contents: """
        struct Helpers {
            // Type pattern matches T -> T but no name signal, no body
            // signal — score 30, lands in Possible tier.
            func process(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )
        #expect(recording.text == "0 suggestions.")
    }

    @Test("--include-possible surfaces Possible-tier suggestions")
    func includePossibleSurfacesPossibleTier() throws {
        let directory = try writeFixture(name: "IncludePossible", contents: """
        struct Helpers {
            func process(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            output: recording
        )
        #expect(recording.text.contains("1 suggestion."))
        #expect(recording.text.contains("(Possible)"))
        #expect(recording.text.contains("process(_:)"))
    }

    @Test("Strong idempotent function renders the §4.5 block end-to-end")
    func strongSuggestionRendersFullBlock() throws {
        let directory = try writeFixture(name: "StrongIdempotent", contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )
        #expect(recording.text.contains("1 suggestion."))
        #expect(recording.text.contains("Template: idempotence"))
        #expect(recording.text.contains("Score:    90 (Strong)"))
        #expect(recording.text.contains("✓ Type-symmetry signature: T -> T (T = String) (+30)"))
        #expect(recording.text.contains("✓ Curated idempotence verb match: 'normalize' (+40)"))
        #expect(recording.text.contains("✓ Self-composition detected in body"))
        #expect(recording.text.contains("⚠ T must conform to Equatable"))
        #expect(recording.text.contains("Generator: not yet computed (M3 prerequisite)"))
        #expect(recording.text.contains("Sampling:  not run (M4 deferred)"))
    }

    @Test("Non-deterministic body suppresses an otherwise-strong candidate")
    func nonDeterministicBodyVetoes() throws {
        let directory = try writeFixture(name: "NonDeterministic", contents: """
        struct Stamper {
            func normalize(_ value: String) -> String {
                _ = Date()
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            output: recording
        )
        #expect(recording.text == "0 suggestions.")
    }

    // MARK: - Helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferCLITests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeFixture(name: String, contents: String) throws -> URL {
        let directory = try makeFixtureDirectory(name: name)
        let file = directory.appendingPathComponent("Source.swift")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return directory
    }
}

/// In-memory output sink used by the pipeline tests so they can assert
/// against rendered text without going through stdout.
private final class RecordingOutput: DiscoverOutput, @unchecked Sendable {
    var text: String = ""
    func write(_ text: String) {
        self.text = text
    }
}
