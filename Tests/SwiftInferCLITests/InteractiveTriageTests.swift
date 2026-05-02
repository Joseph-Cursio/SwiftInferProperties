import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// Tests for all four prompt arms (A/s/n/?), dry-run vs production
// modes, file-write side effects, decisions-update side effects, and
// the suggestion-field extraction helpers — splitting along the
// 250-line limit would scatter the per-arm assertions across files.
// swiftlint:disable type_body_length
@Suite("InteractiveTriage — prompt loop + accept/skip/reject + dry-run (M6.4)")
struct InteractiveTriageTests {

    // MARK: - Empty / no-pending paths

    @Test
    func emptySuggestionsReturnsImmediately() throws {
        let output = TriageRecordingOutput()
        let context = makeContext(
            prompt: TriageRecordingPromptInput(scriptedLines: []),
            output: output
        )
        let result = try InteractiveTriage.run(
            suggestions: [],
            existingDecisions: .empty,
            context: context
        )
        #expect(result.updatedDecisions == .empty)
        #expect(result.writtenFiles.isEmpty)
        #expect(output.lines.contains("No new suggestions to triage."))
    }

    @Test
    func allSuggestionsAlreadyDecidedReturnsImmediately() throws {
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let already = Decisions(records: [
            DecisionRecord(
                identityHash: suggestion.identity.normalized,
                template: "idempotence",
                scoreAtDecision: 90,
                tier: .strong,
                decision: .accepted,
                timestamp: Date(timeIntervalSince1970: 0)
            )
        ])
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: already,
            context: makeContext(prompt: TriageRecordingPromptInput(scriptedLines: []))
        )
        #expect(result.updatedDecisions == already)
        #expect(result.writtenFiles.isEmpty)
    }

    // MARK: - Accept

    @Test
    func acceptOnIdempotenceWritesStubAndRecordsDecision() throws {
        let directory = try makeFixtureDirectory(name: "AcceptIdempotent")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["A"]),
                outputDirectory: directory
            )
        )
        let stored = try #require(result.updatedDecisions.record(for: suggestion.identity.normalized))
        #expect(stored.decision == .accepted)
        #expect(stored.template == "idempotence")
        #expect(result.writtenFiles.count == 1)
        let stubPath = try #require(result.writtenFiles.first)
        #expect(stubPath.path.contains("Tests/Generated/SwiftInfer/idempotence/normalize.swift"))
        let contents = try String(contentsOf: stubPath, encoding: .utf8)
        #expect(contents.contains("@Test func normalize_isIdempotent()"))
        #expect(contents.contains("normalize(normalize(value)) == normalize(value)"))
        #expect(contents.contains("import ProtocolLawKit"))
    }

    @Test
    func acceptOnRoundTripWritesStubWithBothFunctionNames() throws {
        let directory = try makeFixtureDirectory(name: "AcceptRoundTrip")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeRoundTripSuggestion(forwardName: "encode", inverseName: "decode")
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["A"]),
                outputDirectory: directory
            )
        )
        let stubPath = try #require(result.writtenFiles.first)
        #expect(stubPath.path.contains("Tests/Generated/SwiftInfer/round-trip/encode_decode.swift"))
        let contents = try String(contentsOf: stubPath, encoding: .utf8)
        #expect(contents.contains("@Test func encode_decode_roundTrip()"))
        #expect(contents.contains("decode(encode(value)) == value"))
    }

    @Test
    func acceptOnUnsupportedTemplateRecordsDecisionWithoutWritingFile() throws {
        // Commutativity has no LiftedTestEmitter arm in v1 — accept
        // records the decision but the orchestrator emits a `note:`
        // diagnostic and skips the file write.
        let directory = try makeFixtureDirectory(name: "AcceptCommutativity")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeBinarySuggestion(template: "commutativity", funcName: "merge")
        let diagnostics = TriageRecordingDiagnosticOutput()
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["A"]),
                diagnostics: diagnostics,
                outputDirectory: directory
            )
        )
        let stored = try #require(result.updatedDecisions.record(for: suggestion.identity.normalized))
        #expect(stored.decision == .accepted)
        #expect(result.writtenFiles.isEmpty)
        #expect(diagnostics.lines.contains { line in
            line.contains("no stub writeout available for template 'commutativity'")
        })
    }

    // MARK: - Skip + Reject + Empty-line

    @Test
    func skipRecordsDecisionAndWritesNoFile() throws {
        try assertSingleArmRecords(input: "s", expected: .skipped, name: "Skip")
    }

    @Test
    func rejectRecordsDecisionAndWritesNoFile() throws {
        try assertSingleArmRecords(input: "n", expected: .rejected, name: "Reject")
    }

    @Test
    func emptyLineDefaultsToSkip() throws {
        // Pressing Enter with no input defaults to skip — the safe
        // action that doesn't commit anything.
        try assertSingleArmRecords(input: "", expected: .skipped, name: "EmptyLineSkip")
    }

    // MARK: - Help + invalid input

    @Test
    func helpReprompts() throws {
        let directory = try makeFixtureDirectory(name: "Help")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let output = TriageRecordingOutput()
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["?", "s"]),
                output: output,
                outputDirectory: directory
            )
        )
        #expect(output.lines.contains { $0.contains("A — accept this suggestion") })
        let stored = try #require(result.updatedDecisions.record(for: suggestion.identity.normalized))
        #expect(stored.decision == .skipped)
    }

    @Test
    func invalidInputReprompts() throws {
        let directory = try makeFixtureDirectory(name: "Invalid")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let output = TriageRecordingOutput()
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["foo", "s"]),
                output: output,
                outputDirectory: directory
            )
        )
        #expect(output.lines.contains { $0.contains("Unrecognized input 'foo'") })
        let stored = try #require(result.updatedDecisions.record(for: suggestion.identity.normalized))
        #expect(stored.decision == .skipped)
    }

    @Test
    func eofMidPromptDefaultsToSkipForRemainingSuggestions() throws {
        let directory = try makeFixtureDirectory(name: "EOF")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = makeIdempotentSuggestion(funcName: "normalize", typeName: "String", file: "A.swift")
        let second = makeIdempotentSuggestion(funcName: "trim", typeName: "String", file: "B.swift")
        let result = try InteractiveTriage.run(
            suggestions: [first, second],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["A"]),
                outputDirectory: directory
            )
        )
        #expect(result.updatedDecisions.record(for: first.identity.normalized)?.decision == .accepted)
        #expect(result.updatedDecisions.record(for: second.identity.normalized)?.decision == .skipped)
    }

    // MARK: - Dry-run

    @Test
    func dryRunAcceptShowsWouldBePathButWritesNothing() throws {
        let directory = try makeFixtureDirectory(name: "DryRunAccept")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let output = TriageRecordingOutput()
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["A"]),
                output: output,
                outputDirectory: directory,
                dryRun: true
            )
        )
        #expect(result.updatedDecisions == .empty)
        #expect(result.writtenFiles.isEmpty)
        #expect(output.lines.contains { $0.contains("--dry-run in effect") })
        #expect(output.lines.contains { line in
            line.contains("[dry-run] would write")
                && line.contains("Tests/Generated/SwiftInfer/idempotence/normalize.swift")
        })
        let expectedPath = directory
            .appendingPathComponent("Tests/Generated/SwiftInfer/idempotence/normalize.swift")
        #expect(!FileManager.default.fileExists(atPath: expectedPath.path))
    }

    @Test
    func dryRunSkipDoesNotUpdateDecisions() throws {
        let directory = try makeFixtureDirectory(name: "DryRunSkip")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["s"]),
                outputDirectory: directory,
                dryRun: true
            )
        )
        #expect(result.updatedDecisions == .empty)
    }

    // MARK: - Suggestion field extraction

    @Test
    func functionNameExtractsFromDisplayName() {
        #expect(InteractiveTriage.functionName(from: "normalize(_:)") == "normalize")
        #expect(InteractiveTriage.functionName(from: "encode(_:)") == "encode")
        #expect(InteractiveTriage.functionName(from: "merge(_:_:)") == "merge")
        #expect(InteractiveTriage.functionName(from: "normalize") == nil)
    }

    @Test
    func paramTypeExtractsFromSignature() {
        #expect(InteractiveTriage.paramType(from: "(String) -> String") == "String")
        #expect(InteractiveTriage.paramType(from: "(MyType) -> Data") == "MyType")
        #expect(InteractiveTriage.paramType(from: "(Int, Int) -> Int") == "Int")
        #expect(InteractiveTriage.paramType(from: "() -> Int") == nil)
    }

    // MARK: - Helpers

    private func assertSingleArmRecords(
        input: String,
        expected: Decision,
        name: String
    ) throws {
        let directory = try makeFixtureDirectory(name: name)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: [input]),
                outputDirectory: directory
            )
        )
        let stored = try #require(result.updatedDecisions.record(for: suggestion.identity.normalized))
        #expect(stored.decision == expected)
        #expect(result.writtenFiles.isEmpty)
    }

    private func makeContext(
        prompt: TriageRecordingPromptInput,
        output: TriageRecordingOutput = TriageRecordingOutput(),
        diagnostics: TriageRecordingDiagnosticOutput = TriageRecordingDiagnosticOutput(),
        outputDirectory: URL = FileManager.default.temporaryDirectory,
        dryRun: Bool = false
    ) -> InteractiveTriage.Context {
        InteractiveTriage.Context(
            prompt: prompt,
            output: output,
            diagnostics: diagnostics,
            outputDirectory: outputDirectory,
            dryRun: dryRun,
            clock: { Date(timeIntervalSince1970: 0) }
        )
    }

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("InteractiveTriageTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
// swiftlint:enable type_body_length
