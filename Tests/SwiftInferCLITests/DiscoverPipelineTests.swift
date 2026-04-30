import Foundation
import Testing
@testable import SwiftInferCLI

// swiftlint:disable type_body_length
// Test suites cohere around their subject — splitting along the 250-line
// body limit would scatter the discover-pipeline assertions across
// multiple files for no reader benefit.
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

    @Test("Round-trip pair surfaces with curated name match")
    func roundTripFixtureRenders() throws {
        let directory = try writeFixture(name: "RoundTrip", contents: """
        struct MyType {}
        struct Codec {
            func encode(_ value: MyType) -> Data {
                return Data()
            }
            func decode(_ data: Data) -> MyType {
                return MyType()
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
        #expect(recording.text.contains("Template: round-trip"))
        #expect(recording.text.contains("Score:    70 (Likely)"))
        #expect(recording.text.contains("encode(_:)"))
        #expect(recording.text.contains("decode(_:)"))
        #expect(recording.text.contains("✓ Curated inverse name pair: encode/decode (+40)"))
        #expect(recording.text.contains("⚠ Throws on either side"))
    }

    @Test("Skip marker in source suppresses the matching suggestion")
    func skipMarkerSuppressesSuggestion() throws {
        // Identity for: idempotence|Sanitizer.normalize(_:)|(String)->String
        // (computed via SHA256 in SuggestionIdentity)
        let directory = try writeFixture(name: "SkipMarker", contents: """
        // swiftinfer: skip 0xA1C9DEC1AEA2791C
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
        #expect(recording.text == "0 suggestions.")
    }

    @Test("Skip marker for an unrelated hash leaves the suggestion in place")
    func skipMarkerUnrelatedHashIgnored() throws {
        let directory = try writeFixture(name: "SkipUnrelated", contents: """
        // swiftinfer: skip 0xDEADBEEF12345678
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
        #expect(recording.text.contains("Template: idempotence"))
        #expect(recording.text.contains("Score:    90 (Strong)"))
    }

    @Test("Round-trip skip marker suppresses the pair regardless of orientation")
    func skipMarkerRoundTrip() throws {
        // Identity for: round-trip|Codec.decode(_:)|(Data)->MyType|Codec.encode(_:)|(MyType)->Data
        let directory = try writeFixture(name: "SkipRoundTrip", contents: """
        // swiftinfer: skip 0x4C3618BEBBE59391
        struct MyType {}
        struct Codec {
            func encode(_ value: MyType) -> Data {
                return Data()
            }
            func decode(_ data: Data) -> MyType {
                return MyType()
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
        #expect(!recording.text.contains("Template: round-trip"))
    }

    @Test("Non-deterministic body in either round-trip half suppresses the pair")
    func roundTripNonDeterministicVeto() throws {
        let directory = try writeFixture(name: "RoundTripVeto", contents: """
        struct MyType {}
        struct Codec {
            func encode(_ value: MyType) -> Data {
                _ = Date()
                return Data()
            }
            func decode(_ data: Data) -> MyType {
                return MyType()
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
        #expect(!recording.text.contains("Template: round-trip"))
    }

    // MARK: - Vocabulary integration (M2.1)

    @Test("Project-vocabulary idempotence verb flows through to rendered output")
    func projectVocabularyIdempotenceFlowsThrough() throws {
        let directory = try writeFixture(name: "VocabIdempotence", contents: """
        struct Helpers {
            func sanitizeXML(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vocabularyPath = directory.appendingPathComponent("vocabulary.json")
        try Data(#"{ "idempotenceVerbs": ["sanitizeXML"] }"#.utf8).write(to: vocabularyPath)
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            explicitVocabularyPath: vocabularyPath,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text.contains("Score:    70 (Likely)"))
        #expect(recording.text.contains("✓ Project-vocabulary idempotence verb match: 'sanitizeXML' (+40)"))
        #expect(diagnostics.lines.isEmpty)
    }

    @Test("Project-vocabulary inverse pair flows through to round-trip output")
    func projectVocabularyRoundTripFlowsThrough() throws {
        let directory = try writeFixture(name: "VocabRoundTrip", contents: """
        struct Job {}
        struct Queue {
            func enqueue(_ value: Job) -> Job? {
                return value
            }
            func dequeue(_ value: Job?) -> Job {
                return value ?? Job()
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vocabularyPath = directory.appendingPathComponent("vocabulary.json")
        try Data(#"{ "inversePairs": [["enqueue", "dequeue"]] }"#.utf8).write(to: vocabularyPath)
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            explicitVocabularyPath: vocabularyPath,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text.contains("Template: round-trip"))
        #expect(recording.text.contains("✓ Project-vocabulary inverse name pair: enqueue/dequeue (+40)"))
        #expect(diagnostics.lines.isEmpty)
    }

    @Test("Malformed explicit vocabulary path emits a stderr warning and falls back to .empty")
    func malformedVocabularyWarns() throws {
        let directory = try writeFixture(name: "VocabMalformed", contents: """
        struct Helpers {
            func sanitizeXML(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vocabularyPath = directory.appendingPathComponent("vocabulary.json")
        try Data("{ malformed:".utf8).write(to: vocabularyPath)
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            explicitVocabularyPath: vocabularyPath,
            output: recording,
            diagnostics: diagnostics
        )
        // Vocabulary fell back to .empty, so sanitizeXML doesn't fire
        // any name signal — the function only matches type-symmetry (30,
        // Possible) and is hidden behind --include-possible.
        #expect(recording.text == "0 suggestions.")
        #expect(diagnostics.lines.count == 1)
        #expect(diagnostics.lines.first?.hasPrefix("warning: ") == true)
        #expect(diagnostics.lines.first?.contains("could not parse") == true)
    }

    @Test("Absent vocabulary file with no explicit path is silent — no warning, no name signal")
    func absentVocabularyIsSilent() throws {
        let directory = try writeFixture(name: "VocabAbsent", contents: """
        struct Helpers {
            func sanitizeXML(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text == "0 suggestions.")
        #expect(diagnostics.lines.isEmpty)
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
// swiftlint:enable type_body_length

/// In-memory output sink used by the pipeline tests so they can assert
/// against rendered text without going through stdout.
private final class RecordingOutput: DiscoverOutput, @unchecked Sendable {
    var text: String = ""
    func write(_ text: String) {
        self.text = text
    }
}

/// In-memory diagnostic sink used by the M2.1 vocabulary tests to assert
/// against stderr-bound warnings without writing to the real stderr.
private final class RecordingDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    var lines: [String] = []
    func writeDiagnostic(_ text: String) {
        lines.append(text)
    }
}
