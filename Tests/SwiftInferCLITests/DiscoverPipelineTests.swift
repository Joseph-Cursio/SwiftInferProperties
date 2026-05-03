import Foundation
import Testing
@testable import SwiftInferCLI

@Suite("Discover pipeline — basic discovery + skip markers")
struct DiscoverPipelineTests {

    @Test("Empty target directory renders the zero-suggestions sentinel")
    func emptyTargetRendersSentinel() throws {
        let directory = try makeDPFixtureDirectory(name: "EmptyTarget")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )
        #expect(recording.text == "0 suggestions.")
    }

    @Test("Possible-tier suggestions are hidden by default")
    func possibleTierHiddenByDefault() throws {
        let directory = try writeDPFixture(name: "HiddenPossible", contents: """
        struct Helpers {
            // Type pattern matches T -> T but no name signal, no body
            // signal — score 30, lands in Possible tier.
            func process(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )
        #expect(recording.text == "0 suggestions.")
    }

    @Test("--include-possible surfaces Possible-tier suggestions")
    func includePossibleSurfacesPossibleTier() throws {
        let directory = try writeDPFixture(name: "IncludePossible", contents: """
        struct Helpers {
            func process(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            output: recording
        )
        // `process: String -> String` fires both idempotence (type-pattern
        // alone, score 30 = Possible) and monotonicity (M7.1 type-pattern
        // alone, score 25 = Possible) under --include-possible.
        #expect(recording.text.contains("2 suggestions."))
        #expect(recording.text.contains("(Possible)"))
        #expect(recording.text.contains("process(_:)"))
    }

    @Test("Strong idempotent function renders the §4.5 block end-to-end")
    func strongSuggestionRendersFullBlock() throws {
        let directory = try writeDPFixture(name: "StrongIdempotent", contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
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
        #expect(recording.text.contains("Sampling:  not run; lifted test seed: 0x"))
    }

    @Test("Non-deterministic body suppresses an otherwise-strong candidate")
    func nonDeterministicBodyVetoes() throws {
        let directory = try writeDPFixture(name: "NonDeterministic", contents: """
        struct Stamper {
            func normalize(_ value: String) -> String {
                _ = Date()
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            output: recording
        )
        #expect(recording.text == "0 suggestions.")
    }

    @Test("Round-trip pair surfaces with curated name match")
    func roundTripFixtureRenders() throws {
        let directory = try writeDPFixture(name: "RoundTrip", contents: """
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
        let recording = DPRecordingOutput()
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
        let directory = try writeDPFixture(name: "SkipMarker", contents: """
        // swiftinfer: skip 0xA1C9DEC1AEA2791C
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )
        #expect(recording.text == "0 suggestions.")
    }

    @Test("Skip marker for an unrelated hash leaves the suggestion in place")
    func skipMarkerUnrelatedHashIgnored() throws {
        let directory = try writeDPFixture(name: "SkipUnrelated", contents: """
        // swiftinfer: skip 0xDEADBEEF12345678
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
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
        let directory = try writeDPFixture(name: "SkipRoundTrip", contents: """
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
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )
        #expect(!recording.text.contains("Template: round-trip"))
    }

    @Test("Non-deterministic body in either round-trip half suppresses the pair")
    func roundTripNonDeterministicVeto() throws {
        let directory = try writeDPFixture(name: "RoundTripVeto", contents: """
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
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            output: recording
        )
        #expect(!recording.text.contains("Template: round-trip"))
    }
}

@Suite("Discover pipeline — vocabulary integration (M2.1)")
struct DiscoverPipelineVocabularyTests {

    @Test("Project-vocabulary idempotence verb flows through to rendered output")
    func projectVocabularyIdempotenceFlowsThrough() throws {
        let directory = try writeDPFixture(name: "VocabIdempotence", contents: """
        struct Helpers {
            func sanitizeXML(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vocabularyPath = directory.appendingPathComponent("vocabulary.json")
        try Data(#"{ "idempotenceVerbs": ["sanitizeXML"] }"#.utf8).write(to: vocabularyPath)
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
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
        let directory = try writeDPFixture(name: "VocabRoundTrip", contents: """
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
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
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
        let directory = try writeDPFixture(name: "VocabMalformed", contents: """
        struct Helpers {
            func sanitizeXML(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vocabularyPath = directory.appendingPathComponent("vocabulary.json")
        try Data("{ malformed:".utf8).write(to: vocabularyPath)
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            explicitVocabularyPath: vocabularyPath,
            output: recording,
            diagnostics: diagnostics
        )
        // Vocabulary fell back to .empty.
        #expect(recording.text == "0 suggestions.")
        #expect(diagnostics.lines.count == 1)
        #expect(diagnostics.lines.first?.hasPrefix("warning: ") == true)
        #expect(diagnostics.lines.first?.contains("could not parse") == true)
    }

    @Test("Absent vocabulary file with no explicit path is silent — no warning, no name signal")
    func absentVocabularyIsSilent() throws {
        let directory = try writeDPFixture(name: "VocabAbsent", contents: """
        struct Helpers {
            func sanitizeXML(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text == "0 suggestions.")
        #expect(diagnostics.lines.isEmpty)
    }
}
