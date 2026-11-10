import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

@Suite("InteractiveTriage — empty/already-decided + accept paths (M6.4)")
struct InteractiveTriageAcceptTests {

    // MARK: - Empty / no-pending paths

    @Test
    func emptySuggestionsReturnsImmediately() throws {
        let output = TriageRecordingOutput()
        let context = makeTriageContext(
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
            ),
        ])
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: already,
            context: makeTriageContext(prompt: TriageRecordingPromptInput(scriptedLines: []))
        )
        #expect(result.updatedDecisions == already)
        #expect(result.writtenFiles.isEmpty)
    }

    // MARK: - Accept

    @Test
    func acceptOnIdempotenceWritesStubAndRecordsDecision() throws {
        let directory = try makeTriageFixtureDirectory(name: "AcceptIdempotent")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeTriageContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["A"]),
                outputDirectory: directory
            )
        )
        let stored = try #require(result.updatedDecisions.record(for: suggestion.identity.normalized))
        #expect(stored.decision == .accepted)
        #expect(stored.template == "idempotence")
        #expect(result.writtenFiles.count == 1)
        let stubPath = try #require(result.writtenFiles.first)
        #expect(stubPath.path.contains("Tests/Generated/SwiftInfer/idempotence/NormalizeIdempotenceTests.swift"))
        let contents = try String(contentsOf: stubPath, encoding: .utf8)
        #expect(contents.contains("@Test func normalize_isIdempotent()"))
        #expect(contents.contains("normalize(normalize(value)) == normalize(value)"))
        #expect(contents.contains("import PropertyLawKit"))
    }

    @Test
    func acceptOnRoundTripWritesStubWithBothFunctionNames() throws {
        let directory = try makeTriageFixtureDirectory(name: "AcceptRoundTrip")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeRoundTripSuggestion(forwardName: "encode", inverseName: "decode")
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeTriageContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["A"]),
                outputDirectory: directory
            )
        )
        let stubPath = try #require(result.writtenFiles.first)
        #expect(stubPath.path.contains("Tests/Generated/SwiftInfer/round-trip/EncodeDecodeRoundTripTests.swift"))
        let contents = try String(contentsOf: stubPath, encoding: .utf8)
        #expect(contents.contains("@Test func encode_decode_roundTrip()"))
        #expect(contents.contains("decode(encode(value)) == value"))
    }

    @Test
    func acceptOnCommutativityWritesFileViaM8_2EmitterArm() throws {
        // M8.2 added the LiftedTestEmitter.commutative arm — accept now
        // writes a stub file rather than surfacing the v1 "no stub
        // writeout available" diagnostic.
        let directory = try makeTriageFixtureDirectory(name: "AcceptCommutativity")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeBinarySuggestion(template: "commutativity", funcName: "merge")
        let diagnostics = TriageRecordingDiagnosticOutput()
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeTriageContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["A"]),
                diagnostics: diagnostics,
                outputDirectory: directory
            )
        )
        let stored = try #require(result.updatedDecisions.record(for: suggestion.identity.normalized))
        #expect(stored.decision == .accepted)
        let stubPath = try #require(result.writtenFiles.first)
        #expect(stubPath.path.contains("Tests/Generated/SwiftInfer/commutativity/MergeCommutativityTests.swift"))
        let contents = try String(contentsOf: stubPath, encoding: .utf8)
        #expect(contents.contains("@Test func merge_isCommutative()"))
        #expect(contents.contains("merge(pair.0, pair.1) == merge(pair.1, pair.0)"))
        // The "no stub writeout available" diagnostic must NOT fire —
        // M8.2 closes that gap for every shipped template.
        #expect(diagnostics.lines.contains { line in
            line.contains("no stub writeout available")
        } == false)
    }
}
