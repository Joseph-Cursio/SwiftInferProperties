import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V1.98 (cycle-95) — tests for InteractionInteractiveTriage: the
// per-suggestion `[A/C/s/n/?]` prompt-loop that walks a user
// through interaction-invariant suggestions and records decisions
// to .swiftinfer/interaction-decisions.json.

@Suite("InteractionInteractiveTriage — V1.98 per-suggestion triage")
struct InteractionInteractiveTriageTests {

    private let now = ISO8601DateFormatter().date(from: "2026-05-17T10:00:00Z")!

    // MARK: - readChoice — prompt-arm classification

    @Test("V1.98 — readChoice maps each arm to the right Choice")
    func readChoiceClassifications() {
        // Drive readChoice with a single scripted input per call;
        // confirm each maps to the expected Choice. Empty string
        // (just Enter) defaults to .skip, matching v1's posture.
        for (input, expected) in [
            ("a", InteractionInteractiveTriage.Choice.accept),
            ("A", .accept),
            ("c", .acceptAsConformance),
            ("C", .acceptAsConformance),
            ("s", .skip),
            ("", .skip),
            ("n", .reject),
            ("N", .reject)
        ] {
            let prompt = TriageRecordingPromptInput(scriptedLines: [input])
            let output = TriageRecordingOutput()
            let choice = InteractionInteractiveTriage.readChoice(
                prompt: prompt,
                output: output
            )
            #expect(choice == expected, "input '\(input)' should map to \(expected)")
        }
    }

    @Test("V1.98 — readChoice loops on `?` (help) then accepts the next valid input")
    func readChoiceHelpLoops() {
        let prompt = TriageRecordingPromptInput(scriptedLines: ["?", "a"])
        let output = TriageRecordingOutput()
        let choice = InteractionInteractiveTriage.readChoice(
            prompt: prompt,
            output: output
        )
        #expect(choice == .accept)
        // The help text was rendered before the accept was matched.
        #expect(output.text.contains("A — accept this interaction invariant"))
    }

    @Test("V1.98 — readChoice falls through on unrecognized input then accepts the next valid one")
    func readChoiceUnknownThenValid() {
        let prompt = TriageRecordingPromptInput(scriptedLines: ["x", "n"])
        let output = TriageRecordingOutput()
        let choice = InteractionInteractiveTriage.readChoice(
            prompt: prompt,
            output: output
        )
        #expect(choice == .reject)
        #expect(output.text.contains("Unrecognized input 'x'"))
    }

    @Test("V1.98 — readChoice returns .skip on EOF (script exhausted)")
    func readChoiceEOFReturnsSkip() {
        let prompt = TriageRecordingPromptInput(scriptedLines: [])
        let output = TriageRecordingOutput()
        let choice = InteractionInteractiveTriage.readChoice(
            prompt: prompt,
            output: output
        )
        #expect(choice == .skip)
    }

    // MARK: - decisionFor mapping

    @Test("V1.98 — decisionFor maps Choice → InteractionDecision except .skip → nil")
    func decisionForMappings() {
        #expect(InteractionInteractiveTriage.decisionFor(.accept) == .accepted)
        #expect(InteractionInteractiveTriage.decisionFor(.acceptAsConformance) == .acceptedAsConformance)
        #expect(InteractionInteractiveTriage.decisionFor(.reject) == .rejected)
        #expect(InteractionInteractiveTriage.decisionFor(.skip) == nil)
    }

    // MARK: - End-to-end run with scripted choices

    @Test("V1.98 — run records accepted / rejected / skipped across a three-suggestion fixture")
    func runMixedDecisions() throws {
        let directory = try makePackageRoot(name: "RunMixedDecisions")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = [
            makeFixtureSuggestion(predicate: "state.a == 1"),
            makeFixtureSuggestion(predicate: "state.b == 2"),
            makeFixtureSuggestion(predicate: "state.c == 3")
        ]
        let prompt = TriageRecordingPromptInput(scriptedLines: ["a", "s", "n"])
        let output = TriageRecordingOutput()
        let diagnostics = TriageRecordingDiagnosticOutput()
        let updated = try InteractionInteractiveTriage.run(
            suggestions: suggestions,
            packageRoot: directory,
            inputs: InteractionInteractiveTriage.Inputs(
                prompt: prompt,
                output: output,
                diagnostics: diagnostics,
                dryRun: false,
                now: now
            )
        )
        // Accepted + rejected each persist a record; skipped does
        // not. Two records total.
        #expect(updated.records.count == 2)
        let byHash = Dictionary(uniqueKeysWithValues: updated.records.map { ($0.identityHash, $0) })
        #expect(byHash[suggestions[0].identity.normalized]?.decision == .accepted)
        #expect(byHash[suggestions[1].identity.normalized] == nil)
        #expect(byHash[suggestions[2].identity.normalized]?.decision == .rejected)
        // Decisions file was persisted.
        let path = directory.appendingPathComponent(".swiftinfer/interaction-decisions.json")
        #expect(FileManager.default.fileExists(atPath: path.path))
    }

    @Test("V1.98 — Conformance arm records acceptedAsConformance")
    func conformanceArmRecordsCorrectly() throws {
        let directory = try makePackageRoot(name: "ConformanceArm")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeFixtureSuggestion(predicate: "state.x == 1")
        let prompt = TriageRecordingPromptInput(scriptedLines: ["c"])
        let output = TriageRecordingOutput()
        let diagnostics = TriageRecordingDiagnosticOutput()
        let updated = try InteractionInteractiveTriage.run(
            suggestions: [suggestion],
            packageRoot: directory,
            inputs: InteractionInteractiveTriage.Inputs(
                prompt: prompt,
                output: output,
                diagnostics: diagnostics,
                dryRun: false,
                now: now
            )
        )
        #expect(updated.records.count == 1)
        #expect(updated.records[0].decision == .acceptedAsConformance)
    }

    @Test("V1.98 — dryRun = true skips persistence but still walks the loop")
    func dryRunSkipsPersistence() throws {
        let directory = try makePackageRoot(name: "DryRun")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeFixtureSuggestion(predicate: "state.x == 1")
        let prompt = TriageRecordingPromptInput(scriptedLines: ["a"])
        let output = TriageRecordingOutput()
        let diagnostics = TriageRecordingDiagnosticOutput()
        let updated = try InteractionInteractiveTriage.run(
            suggestions: [suggestion],
            packageRoot: directory,
            inputs: InteractionInteractiveTriage.Inputs(
                prompt: prompt,
                output: output,
                diagnostics: diagnostics,
                dryRun: true,
                now: now
            )
        )
        // The in-memory result has the accepted record …
        #expect(updated.records.count == 1)
        #expect(updated.records[0].decision == .accepted)
        // … but the file was NOT written.
        let path = directory.appendingPathComponent(".swiftinfer/interaction-decisions.json")
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    @Test("V1.98 — existing decisions are loaded and upserted on subsequent triage")
    func existingDecisionsAreUpserted() throws {
        let directory = try makePackageRoot(name: "Upsert")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeFixtureSuggestion(predicate: "state.x == 1")
        // Pre-seed a `.skipped` decision for this identity.
        let prior = InteractionDecisions(records: [
            InteractionDecisionRecord(
                identityHash: suggestion.identity.normalized,
                family: suggestion.family,
                scoreAtDecision: suggestion.score,
                tier: suggestion.tier,
                reducerQualifiedName: suggestion.reducerQualifiedName,
                decision: .skipped,
                timestamp: now
            )
        ])
        let path = directory.appendingPathComponent(".swiftinfer/interaction-decisions.json")
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try InteractionDecisionsLoader.write(prior, to: path)
        // Accept it this time; the record is upserted (one entry,
        // now .accepted).
        let prompt = TriageRecordingPromptInput(scriptedLines: ["a"])
        let output = TriageRecordingOutput()
        let diagnostics = TriageRecordingDiagnosticOutput()
        let updated = try InteractionInteractiveTriage.run(
            suggestions: [suggestion],
            packageRoot: directory,
            inputs: InteractionInteractiveTriage.Inputs(
                prompt: prompt,
                output: output,
                diagnostics: diagnostics,
                dryRun: false,
                now: now
            )
        )
        #expect(updated.records.count == 1)
        #expect(updated.records[0].decision == .accepted)
    }

    // MARK: - Helpers

    private func makePackageRoot(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("InteractionInteractiveTriageTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("// stub manifest".utf8)
            .write(to: base.appendingPathComponent("Package.swift"))
        return base
    }

    private func makeFixtureSuggestion(
        predicate: String,
        family: InteractionInvariantFamily = .conservation
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: family,
            reducerQualifiedName: "Inbox.reduce",
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: family,
            reducerQualifiedName: "Inbox.reduce",
            reducerLocation: "F.swift:1",
            stateTypeName: "Inbox.State",
            actionTypeName: "Inbox.Action",
            predicate: predicate,
            score: 30,
            tier: .possible,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: now
        )
    }
}
