import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// MARK: - Shared helpers

func makeTriageContext(
    prompt: TriageRecordingPromptInput,
    output: TriageRecordingOutput = TriageRecordingOutput(),
    diagnostics: TriageRecordingDiagnosticOutput = TriageRecordingDiagnosticOutput(),
    outputDirectory: URL = FileManager.default.temporaryDirectory,
    dryRun: Bool = false,
    verifyEvidenceByIdentity: [String: VerifyEvidence] = [:]
) -> InteractiveTriage.Context {
    InteractiveTriage.Context(
        prompt: prompt,
        output: output,
        diagnostics: diagnostics,
        outputDirectory: outputDirectory,
        dryRun: dryRun,
        clock: { Date(timeIntervalSince1970: 0) },
        verifyEvidenceByIdentity: verifyEvidenceByIdentity
    )
}

func makeTriageFixtureDirectory(name: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("InteractiveTriageTests-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

private func assertTriageSingleArmRecords(
    input: String,
    expected: Decision,
    name: String
) throws {
    let directory = try makeTriageFixtureDirectory(name: name)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
    let result = try InteractiveTriage.run(
        suggestions: [suggestion],
        existingDecisions: .empty,
        context: makeTriageContext(
            prompt: TriageRecordingPromptInput(scriptedLines: [input]),
            outputDirectory: directory
        )
    )
    let stored = try #require(result.updatedDecisions.record(for: suggestion.identity.normalized))
    #expect(stored.decision == expected)
    #expect(result.writtenFiles.isEmpty)
}

@Suite("InteractiveTriage — skip/reject/help/dry-run/extraction (M6.4)")
struct InteractiveTriageBehaviorTests {

    // MARK: - Skip + Reject + Empty-line

    @Test
    func skipRecordsDecisionAndWritesNoFile() throws {
        try assertTriageSingleArmRecords(input: "s", expected: .skipped, name: "Skip")
    }

    @Test
    func rejectRecordsDecisionAndWritesNoFile() throws {
        try assertTriageSingleArmRecords(input: "n", expected: .rejected, name: "Reject")
    }

    @Test
    func emptyLineDefaultsToSkip() throws {
        // Pressing Enter with no input defaults to skip — the safe
        // action that doesn't commit anything.
        try assertTriageSingleArmRecords(input: "", expected: .skipped, name: "EmptyLineSkip")
    }

    // MARK: - Help + invalid input

    @Test
    func helpReprompts() throws {
        let directory = try makeTriageFixtureDirectory(name: "Help")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let output = TriageRecordingOutput()
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeTriageContext(
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
        let directory = try makeTriageFixtureDirectory(name: "Invalid")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let output = TriageRecordingOutput()
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeTriageContext(
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
        let directory = try makeTriageFixtureDirectory(name: "EOF")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = makeIdempotentSuggestion(funcName: "normalize", typeName: "String", file: "A.swift")
        let second = makeIdempotentSuggestion(funcName: "trim", typeName: "String", file: "B.swift")
        let result = try InteractiveTriage.run(
            suggestions: [first, second],
            existingDecisions: .empty,
            context: makeTriageContext(
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
        let directory = try makeTriageFixtureDirectory(name: "DryRunAccept")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let output = TriageRecordingOutput()
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeTriageContext(
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
                && line.contains("Tests/Generated/SwiftInfer/idempotence/NormalizeIdempotenceTests.swift")
        })
        let expectedPath = directory
            .appendingPathComponent("Tests/Generated/SwiftInfer/idempotence/NormalizeIdempotenceTests.swift")
        #expect(!FileManager.default.fileExists(atPath: expectedPath.path))
    }

    @Test
    func dryRunSkipDoesNotUpdateDecisions() throws {
        let directory = try makeTriageFixtureDirectory(name: "DryRunSkip")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeTriageContext(
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

    @Test
    func returnTypeStripsTrailingPreservingClause() {
        // Existing M7.3 contract — preserved alongside the new `seed`
        // suffix handling.
        #expect(InteractiveTriage.returnType(from: "(Widget) -> Widget preserving \\.isValid") == "Widget")
    }

    @Test
    func returnTypeStripsTrailingSeedClauseFromLiftedReduceEquivalence() {
        // M5.5 — lifted reduceEquivalence promotion encodes the seed in
        // the signature as ` seed <expr>` after the return type. The
        // returnType extractor must strip this suffix so the upstream
        // `paramType` / `returnType` consumers see the `(T, T) -> T`
        // shape they expect.
        #expect(InteractiveTriage.returnType(from: "(Int, Int) -> Int seed 0") == "Int")
        #expect(InteractiveTriage.returnType(from: "(Money, Money) -> Money seed .zero") == "Money")
    }

    @Test
    func seedSourceExtractsLiftedReduceEquivalenceSeedSuffix() {
        // M5.5 — `liftedReduceEquivalenceStub` consumes this extractor
        // to thread the test-body's seed expression into the rendered
        // `xs.reduce(<seed>, <op>)` test.
        #expect(InteractiveTriage.seedSource(from: "(Int, Int) -> Int seed 0") == "0")
        #expect(InteractiveTriage.seedSource(from: "(Money, Money) -> Money seed .zero") == ".zero")
        #expect(InteractiveTriage.seedSource(from: "(Int, Int) -> Int") == nil)
    }
}
