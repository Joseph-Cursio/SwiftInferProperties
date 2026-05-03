import Foundation
import Testing
@testable import SwiftInferCLI

@Suite("Discover pipeline — config integration (M2.2) + commutativity (M2.3)")
struct DiscoverPipelineConfigTests {

    // MARK: - Config integration (M2.2)

    @Test("Config-set includePossible:true surfaces Possible-tier suggestions when CLI is unset")
    func configIncludePossibleTrueSurfacesPossible() throws {
        let directory = try writeDPFixture(name: "ConfigPossibleTrue", contents: """
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
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: nil,
            explicitConfigPath: configPath,
            output: recording,
            diagnostics: diagnostics
        )
        // `process: String -> String` fires both idempotence + monotonicity.
        #expect(recording.text.contains("2 suggestions."))
        #expect(recording.text.contains("(Possible)"))
        #expect(diagnostics.lines.isEmpty)
    }

    @Test("CLI includePossible:true wins over config-set false")
    func cliWinsOverConfigForIncludePossibleTrue() throws {
        let directory = try writeDPFixture(name: "CliOverConfigTrue", contents: """
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
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
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
        let directory = try writeDPFixture(name: "CliOverConfigFalse", contents: """
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
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
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
        let root = try makeDPFixtureDirectory(name: "ConfigVocabPath")
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

        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
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
        let directory = try writeDPFixture(name: "CliOverConfigVocab", contents: """
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

        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            explicitVocabularyPath: cliVocabPath,
            explicitConfigPath: configPath,
            output: recording,
            diagnostics: diagnostics
        )
        // CLI vocab includes sanitizeXML → project-vocab signal fires.
        #expect(recording.text.contains("✓ Project-vocabulary idempotence verb match: 'sanitizeXML' (+40)"))
        #expect(diagnostics.lines.isEmpty)
    }

    // MARK: - Commutativity (M2.3)

    @Test("Commutativity fixture surfaces the new template end-to-end")
    func commutativityFixtureRenders() throws {
        let directory = try writeDPFixture(name: "CommutativityUnion", contents: """
        struct IntSet {
            func merge(_ lhs: IntSet, _ rhs: IntSet) -> IntSet {
                return lhs
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
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
        let directory = try writeDPFixture(name: "CommutativityAnti", contents: """
        struct Strings {
            func concatenate(_ a: [String], _ b: [String]) -> [String] {
                return a + b
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            output: recording,
            diagnostics: diagnostics
        )
        // 30 type-symmetry + (-30) anti-commutativity = 0 → suppressed.
        #expect(!recording.text.contains("Template: commutativity"))
        #expect(diagnostics.lines.isEmpty)
    }

    @Test("Project-vocabulary commutativity verb fires through the pipeline")
    func projectVocabularyCommutativityFlowsThrough() throws {
        let directory = try writeDPFixture(name: "CommutativityProjectVocab", contents: """
        struct Graph {
            func unionGraphs(_ a: Graph, _ b: Graph) -> Graph {
                return a
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vocabularyPath = directory.appendingPathComponent("vocabulary.json")
        try Data(#"{ "commutativityVerbs": ["unionGraphs"] }"#.utf8).write(to: vocabularyPath)
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
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
        let directory = try writeDPFixture(name: "ConfigMalformed", contents: """
        struct Helpers {
            func process(_ value: String) -> String {
                return value
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configPath = directory.appendingPathComponent("config.toml")
        try Data("[discover\nbroken".utf8).write(to: configPath)
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
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
}
