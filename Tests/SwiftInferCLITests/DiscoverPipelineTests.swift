import Foundation
import Testing
@testable import SwiftInferCLI

// swiftlint:disable type_body_length file_length
// The discover pipeline integrates four moving parts (templates,
// vocabulary, config, skip markers); the suite has grown past the
// default body/file limits as M2 features land. Splitting along the
// limits would scatter related end-to-end assertions across multiple
// files for no reader benefit.
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
        // M4.3 §16 #6 — the seed is rendered inline so the lifted
        // test stub picks it up (M5+); we don't pin the exact hex
        // here because the identity hash is asserted elsewhere.
        #expect(recording.text.contains("Sampling:  not run; lifted test seed: 0x"))
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

    // MARK: - Config integration (M2.2)

    @Test("Config-set includePossible:true surfaces Possible-tier suggestions when CLI is unset")
    func configIncludePossibleTrueSurfacesPossible() throws {
        let directory = try writeFixture(name: "ConfigPossibleTrue", contents: """
        struct Helpers {
            func process(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configPath = directory.appendingPathComponent("config.toml")
        try Data("""
        [discover]
        includePossible = true
        """.utf8).write(to: configPath)
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: nil,
            explicitConfigPath: configPath,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text.contains("1 suggestion."))
        #expect(recording.text.contains("(Possible)"))
        #expect(diagnostics.lines.isEmpty)
    }

    @Test("CLI includePossible:true wins over config-set false")
    func cliWinsOverConfigForIncludePossibleTrue() throws {
        let directory = try writeFixture(name: "CliOverConfigTrue", contents: """
        struct Helpers {
            func process(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configPath = directory.appendingPathComponent("config.toml")
        try Data("""
        [discover]
        includePossible = false
        """.utf8).write(to: configPath)
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            explicitConfigPath: configPath,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text.contains("(Possible)"))
        #expect(diagnostics.lines.isEmpty)
    }

    @Test("CLI includePossible:false wins over config-set true")
    func cliWinsOverConfigForIncludePossibleFalse() throws {
        let directory = try writeFixture(name: "CliOverConfigFalse", contents: """
        struct Helpers {
            func process(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configPath = directory.appendingPathComponent("config.toml")
        try Data("""
        [discover]
        includePossible = true
        """.utf8).write(to: configPath)
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            explicitConfigPath: configPath,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text == "0 suggestions.")
        #expect(diagnostics.lines.isEmpty)
    }

    @Test("Config-set vocabularyPath flows through to project-vocab signal")
    func configVocabularyPathFlowsThrough() throws {
        // Use a Package.swift sentinel so ConfigLoader's walk-up resolves
        // the relative vocabularyPath against this directory.
        let root = try makeFixtureDirectory(name: "ConfigVocabPath")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: root.appendingPathComponent("Package.swift"))
        let configDir = root.appendingPathComponent(".swiftinfer")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try Data("""
        [discover]
        vocabularyPath = ".swiftinfer/custom-vocab.json"
        """.utf8).write(to: configDir.appendingPathComponent("config.toml"))
        try Data(#"{ "idempotenceVerbs": ["sanitizeXML"] }"#.utf8)
            .write(to: configDir.appendingPathComponent("custom-vocab.json"))
        let target = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try """
        struct Helpers {
            func sanitizeXML(_ value: String) -> String {
                return value
            }
        }
        """.write(to: target.appendingPathComponent("Source.swift"), atomically: true, encoding: .utf8)

        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: target,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text.contains("Score:    70 (Likely)"))
        #expect(recording.text.contains("✓ Project-vocabulary idempotence verb match: 'sanitizeXML' (+40)"))
        #expect(diagnostics.lines.isEmpty)
    }

    @Test("CLI --vocabulary wins over config-set vocabularyPath")
    func cliVocabularyOverridesConfig() throws {
        let directory = try writeFixture(name: "CliOverConfigVocab", contents: """
        struct Helpers {
            func sanitizeXML(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configPath = directory.appendingPathComponent("config.toml")
        let stubVocabPath = directory.appendingPathComponent("stub.json")
        try Data(#"{ "idempotenceVerbs": ["differentVerb"] }"#.utf8).write(to: stubVocabPath)
        try Data("""
        [discover]
        vocabularyPath = "stub.json"
        """.utf8).write(to: configPath)
        let cliVocabPath = directory.appendingPathComponent("cli-vocab.json")
        try Data(#"{ "idempotenceVerbs": ["sanitizeXML"] }"#.utf8).write(to: cliVocabPath)

        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            explicitVocabularyPath: cliVocabPath,
            explicitConfigPath: configPath,
            output: recording,
            diagnostics: diagnostics
        )
        // The CLI vocab includes sanitizeXML → project-vocab signal fires.
        // The config vocab has differentVerb → wouldn't have fired.
        #expect(recording.text.contains("✓ Project-vocabulary idempotence verb match: 'sanitizeXML' (+40)"))
        #expect(diagnostics.lines.isEmpty)
    }

    // MARK: - Commutativity (M2.3)

    @Test("Commutativity fixture surfaces the new template end-to-end")
    func commutativityFixtureRenders() throws {
        let directory = try writeFixture(name: "CommutativityUnion", contents: """
        struct IntSet {
            func merge(_ lhs: IntSet, _ rhs: IntSet) -> IntSet {
                return lhs
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text.contains("Template: commutativity"))
        #expect(recording.text.contains("Score:    70 (Likely)"))
        #expect(recording.text.contains("✓ Type-symmetry signature: (T, T) -> T (T = IntSet) (+30)"))
        #expect(recording.text.contains("✓ Curated commutativity verb match: 'merge' (+40)"))
        #expect(diagnostics.lines.isEmpty)
    }

    @Test("Anti-commutativity verb on commutativity-shape function is suppressed even with --include-possible")
    func antiCommutativityVerbSuppressed() throws {
        let directory = try writeFixture(name: "CommutativityAnti", contents: """
        struct Strings {
            func concatenate(_ a: [String], _ b: [String]) -> [String] {
                return a + b
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            output: recording,
            diagnostics: diagnostics
        )
        // 30 type-symmetry + (-30) anti-commutativity = 0 → suppressed,
        // hidden regardless of --include-possible.
        #expect(!recording.text.contains("Template: commutativity"))
        #expect(diagnostics.lines.isEmpty)
    }

    @Test("Project-vocabulary commutativity verb fires through the pipeline")
    func projectVocabularyCommutativityFlowsThrough() throws {
        let directory = try writeFixture(name: "CommutativityProjectVocab", contents: """
        struct Graph {
            func unionGraphs(_ a: Graph, _ b: Graph) -> Graph {
                return a
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vocabularyPath = directory.appendingPathComponent("vocabulary.json")
        try Data(#"{ "commutativityVerbs": ["unionGraphs"] }"#.utf8).write(to: vocabularyPath)
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            explicitVocabularyPath: vocabularyPath,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text.contains("Template: commutativity"))
        #expect(recording.text.contains("Score:    70 (Likely)"))
        #expect(recording.text.contains("✓ Project-vocabulary commutativity verb match: 'unionGraphs' (+40)"))
        #expect(diagnostics.lines.isEmpty)
    }

    @Test("Malformed explicit config path emits a stderr warning and falls back to defaults")
    func malformedConfigWarns() throws {
        let directory = try writeFixture(name: "ConfigMalformed", contents: """
        struct Helpers {
            func process(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configPath = directory.appendingPathComponent("config.toml")
        try Data("[discover\nbroken".utf8).write(to: configPath)
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            explicitConfigPath: configPath,
            output: recording,
            diagnostics: diagnostics
        )
        // Defaults → Possible tier hidden → 0 suggestions.
        #expect(recording.text == "0 suggestions.")
        #expect(diagnostics.lines.count == 1)
        #expect(diagnostics.lines.first?.hasPrefix("warning: ") == true)
        #expect(diagnostics.lines.first?.contains("could not parse") == true)
    }

    // MARK: - Contradiction detection (M3.4) — byte-stable diagnostics + elision

    @Test("Commutativity contradiction emits byte-stable stderr diagnostic")
    func commutativityContradictionEmitsByteStableDiagnostic() throws {
        // Single fixture line so the column/line positions are pinned —
        // `merge(_:_:)` lands at line 2 of Source.swift.
        let directory = try writeFixture(name: "ContradictionCommGolden", contents: """
        struct AnyMixer {
            func merge(_ first: Any, _ second: Any) -> Any { return first }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording,
            diagnostics: diagnostics
        )
        let normalized = normalizeDiagnostics(diagnostics.lines, fixture: directory)
        let expected = [
            "contradiction: dropped commutativity suggestion for merge(_:_:)"
                + " at <FIXTURE>/Source.swift:2 — type 'Any' is not Equatable (PRD §5.6 #2)"
        ]
        #expect(normalized == expected)
    }

    @Test("Round-trip contradiction emits byte-stable stderr diagnostic")
    func roundTripContradictionEmitsByteStableDiagnostic() throws {
        // wrap on line 2, unwrap on line 3 — wrap is the canonical
        // forward (sorted by file/line), so the diagnostic anchors there.
        let directory = try writeFixture(name: "ContradictionRTGolden", contents: """
        struct Wrapper {
            func wrap(_ closure: (Int) -> Int) -> Data { return Data() }
            func unwrap(_ raw: Data) -> (Int) -> Int { return { value in value } }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording,
            diagnostics: diagnostics
        )
        let normalized = normalizeDiagnostics(diagnostics.lines, fixture: directory)
        let expected = [
            "contradiction: dropped round-trip suggestion for wrap(_:)"
                + " at <FIXTURE>/Source.swift:2 — type '(Int) -> Int' is not Equatable (PRD §5.6 #3)"
        ]
        #expect(normalized == expected)
    }

    @Test("Contradiction-dropped commutativity suggestion is elided from stdout")
    func contradictionDroppedSuggestionIsElidedFromStdout() throws {
        // `combineAny` isn't in any curated naming list — both commutativity
        // and associativity score 30 (just type-symmetry) → Possible.
        // Default flags hide Possible-tier output, so stdout must render
        // the zero-suggestions sentinel. The contradiction filter still
        // runs at suggestion-collection time, so stderr must still carry
        // the commutativity drop diagnostic.
        let directory = try writeFixture(name: "ContradictionElide", contents: """
        struct AnyMixer {
            func combineAny(_ first: Any, _ second: Any) -> Any { return first }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text == "0 suggestions.")
        #expect(diagnostics.lines.count == 1)
        #expect(diagnostics.lines.first?.contains("commutativity") == true)
    }

    @Test("Contradiction drop only elides the offending template — sibling templates over the same function survive")
    func contradictionDropPreservesUnrelatedSiblingTemplates() throws {
        // `merge` matches both commutativity and associativity (shared
        // verb list per v0.2 §5.2). The §5.6 #2 contradiction layer
        // drops *only* commutativity — associativity over `Any` is
        // structurally inert at M3 (it's an M7 algebraic-structure-cluster
        // concern). Plus `normalize` adds an unrelated idempotence
        // suggestion. Stdout should carry idempotence + associativity;
        // stderr should carry exactly one commutativity drop line.
        let directory = try writeFixture(name: "ContradictionMixed", contents: """
        struct Mix {
            func normalize(_ value: String) -> String { return normalize(normalize(value)) }
            func merge(_ first: Any, _ second: Any) -> Any { return first }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text.contains("2 suggestions."))
        #expect(recording.text.contains("Template: idempotence"))
        #expect(recording.text.contains("Template: associativity"))
        #expect(!recording.text.contains("Template: commutativity"))
        #expect(diagnostics.lines.count == 1)
        #expect(diagnostics.lines.first?.contains("commutativity") == true)
    }

    // MARK: - Generator selection (M4.2) — CLI integration

    @Test("CLI surfaces .derivedMemberwise generator line for struct-typed property")
    func cliRendersDerivedMemberwiseGenerator() throws {
        let directory = try writeFixture(name: "GenSelectMemberwiseCLI", contents: """
        struct Money {
            let amount: Int
            let currency: String
        }
        struct Sanitizer {
            func normalize(_ value: Money) -> Money {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording
        )
        #expect(recording.text.contains("Generator: .derivedMemberwise, confidence: .medium"))
        #expect(recording.text.contains("Sampling:  not run; lifted test seed: 0x"))
    }

    @Test("CLI surfaces .derivedCaseIterable generator line for enum: CaseIterable property")
    func cliRendersDerivedCaseIterableGenerator() throws {
        let directory = try writeFixture(name: "GenSelectCaseIterCLI", contents: """
        enum Side: CaseIterable {
            case left, right
        }
        struct Helpers {
            func normalize(_ value: Side) -> Side {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording
        )
        #expect(recording.text.contains("Generator: .derivedCaseIterable, confidence: .high"))
    }

    @Test("CLI surfaces .derivedRawRepresentable generator line for raw-value enum property")
    func cliRendersDerivedRawRepresentableGenerator() throws {
        let directory = try writeFixture(name: "GenSelectRawRepCLI", contents: """
        enum StatusCode: Int {
            case ok = 200, notFound = 404
        }
        struct Helpers {
            func normalize(_ value: StatusCode) -> StatusCode {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording
        )
        #expect(recording.text.contains("Generator: .derivedRawRepresentable, confidence: .high"))
    }

    @Test("CLI surfaces .registered generator line for static gen() property")
    func cliRendersRegisteredGenerator() throws {
        let directory = try writeFixture(name: "GenSelectUserGenCLI", contents: """
        struct Widget {
            let id: Int
            static func gen() -> Int { 0 }
        }
        struct Helpers {
            func normalize(_ value: Widget) -> Widget {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording
        )
        #expect(recording.text.contains("Generator: .registered, confidence: .high"))
    }

    @Test("CLI surfaces .todo generator line (no confidence) for class-typed property")
    func cliRendersTodoGenerator() throws {
        let directory = try writeFixture(name: "GenSelectTodoCLI", contents: """
        class Logger {
            let prefix: String = ""
        }
        struct Helpers {
            func normalize(_ value: Logger) -> Logger {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = RecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording
        )
        #expect(recording.text.contains("Generator: .todo"))
        // .todo carries nil confidence — the renderer omits the
        // confidence fragment in that case.
        #expect(!recording.text.contains("Generator: .todo, confidence:"))
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

    /// Substitute the dynamic fixture-directory absolute path with a
    /// `<FIXTURE>` placeholder so byte-stable goldens can pin the rest
    /// of the diagnostic line. macOS sometimes canonicalises tmp paths
    /// through the `/private` symlink during scan (`/var/folders/...`
    /// → `/private/var/folders/...`); we substitute both forms,
    /// longest-first, so whichever shape lands in the diagnostic
    /// normalises identically.
    private func normalizeDiagnostics(
        _ lines: [String],
        fixture directory: URL
    ) -> [String] {
        let raw = directory.path
        let withPrivatePrefix = raw.hasPrefix("/private") ? raw : "/private" + raw
        let withoutPrivatePrefix = raw.hasPrefix("/private/")
            ? String(raw.dropFirst("/private".count))
            : raw
        let candidates = [withPrivatePrefix, withoutPrivatePrefix, raw]
            .sorted { $0.count > $1.count }
        return lines.map { line in
            var result = line
            for path in candidates {
                result = result.replacingOccurrences(of: path, with: "<FIXTURE>")
            }
            return result
        }
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
