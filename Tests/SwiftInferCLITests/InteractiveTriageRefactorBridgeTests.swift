import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

@Suite("InteractiveTriage — RefactorBridge [A/B/s/n/?] arm (M7.5c)")
struct InteractiveTriageRefactorBridgeTests {

    // MARK: - Prompt rendering

    @Test("Prompt collapses to [A/s/n/?] when no proposal is attached")
    func promptOmitsBWhenNoProposal() {
        let line = InteractiveTriage.promptLine(position: 1, total: 1, proposalAvailable: false)
        #expect(line == "[1/1] Accept (A) / Skip (s) / Reject (n) / Help (?)")
    }

    @Test("Prompt extends to [A/B/s/n/?] when proposal is attached")
    func promptIncludesBWhenProposalAttached() {
        let line = InteractiveTriage.promptLine(position: 2, total: 5, proposalAvailable: true)
        #expect(line == "[2/5] Accept (A) / Conformance (B) / Skip (s) / Reject (n) / Help (?)")
    }

    @Test("Help text mentions B only when proposal is attached")
    func helpTextConditional() {
        let withB = InteractiveTriage.helpText(proposalAvailable: true)
        let withoutB = InteractiveTriage.helpText(proposalAvailable: false)
        #expect(withB.contains("B — accept Option B (RefactorBridge"))
        #expect(withoutB.contains("B —") == false)
    }

    // MARK: - readChoice gating

    @Test("`b` is recognized only when proposalAvailable is true")
    func bRequiresProposalAvailable() {
        let outputWithProposal = TriageRecordingOutput()
        let promptWithProposal = TriageRecordingPromptInput(scriptedLines: ["b"])
        let choiceWith = InteractiveTriage.readChoice(
            prompt: promptWithProposal,
            output: outputWithProposal,
            proposalAvailable: true
        )
        switch choiceWith {
        case .conformance: break
        default: Issue.record("expected .conformance when proposal available, got \(choiceWith)")
        }

        let outputWithout = TriageRecordingOutput()
        // Script: `b` (rejected) → `s` (default). The `b` should fall to
        // the unrecognized-input branch and re-prompt; `s` advances.
        let promptWithout = TriageRecordingPromptInput(scriptedLines: ["b", "s"])
        let choiceWithout = InteractiveTriage.readChoice(
            prompt: promptWithout,
            output: outputWithout,
            proposalAvailable: false
        )
        switch choiceWithout {
        case .skip: break
        default: Issue.record("expected fallthrough to .skip when no proposal, got \(choiceWithout)")
        }
        #expect(outputWithout.lines.contains { $0.contains("Unrecognized input 'b'") })
    }

    // MARK: - B accept end-to-end

    @Test("B accept writes a Semigroup conformance file and records .acceptedAsConformance")
    func bAcceptWritesSemigroupExtension() throws {
        let directory = try makeFixtureDirectory(name: "BAcceptSemigroup")
        defer { try? FileManager.default.removeItem(at: directory) }
        let assoc = makeBinarySuggestion(template: "associativity", funcName: "merge")
        let proposal = RefactorBridgeProposal(
            typeName: "IntSet",
            protocolName: "Semigroup",
            combineWitness: "merge",
            identityWitness: nil,
            explainability: ExplainabilityBlock(whySuggested: ["op match"], whyMightBeWrong: ["assoc not verified"]),
            relatedIdentities: [assoc.identity]
        )
        let result = try InteractiveTriage.run(
            suggestions: [assoc],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["B"]),
                outputDirectory: directory,
                proposalsByType: ["IntSet": proposal]
            )
        )
        let stored = try #require(result.updatedDecisions.record(for: assoc.identity.normalized))
        #expect(stored.decision == .acceptedAsConformance)
        let path = try #require(result.writtenFiles.first)
        #expect(path.path.contains("Tests/Generated/SwiftInferRefactors/IntSet/Semigroup.swift"))
        let contents = try String(contentsOf: path, encoding: .utf8)
        // M7.5.a — emitter aliases the user's `merge` op into the
        // kit's required `static func combine(_:_:)`.
        #expect(contents.contains("extension IntSet: Semigroup {"))
        #expect(contents.contains("public static func combine(_ lhs: IntSet, _ rhs: IntSet) -> IntSet {"))
        #expect(contents.contains("Self.merge(lhs, rhs)"))
        #expect(contents.contains("import ProtocolLawKit"))
        #expect(contents.contains("RefactorBridge proposal: IntSet → Semigroup"))
    }

    @Test("B accept on Monoid proposal writes a Monoid extension with combine + identity aliasing")
    func bAcceptWritesMonoidExtension() throws {
        let directory = try makeFixtureDirectory(name: "BAcceptMonoid")
        defer { try? FileManager.default.removeItem(at: directory) }
        let assoc = makeBinarySuggestion(template: "associativity", funcName: "merge")
        let proposal = RefactorBridgeProposal(
            typeName: "IntSet",
            protocolName: "Monoid",
            combineWitness: "merge",
            identityWitness: "empty",
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            relatedIdentities: [assoc.identity]
        )
        let result = try InteractiveTriage.run(
            suggestions: [assoc],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["B"]),
                outputDirectory: directory,
                proposalsByType: ["IntSet": proposal]
            )
        )
        let path = try #require(result.writtenFiles.first)
        #expect(path.path.contains("Tests/Generated/SwiftInferRefactors/IntSet/Monoid.swift"))
        let contents = try String(contentsOf: path, encoding: .utf8)
        // M7.5.a — emitter aliases both `merge` (binary op) and
        // `empty` (identity element) into the kit's required statics.
        #expect(contents.contains("extension IntSet: Monoid {"))
        #expect(contents.contains("Self.merge(lhs, rhs)"))
        #expect(contents.contains("public static var identity: IntSet { Self.empty }"))
    }

    // MARK: - Per-type aggregation (open decision #7)

    @Test("Once user picks B for type T, subsequent suggestions on T collapse to [A/s/n/?]")
    func perTypeAggregationCollapsesPromptAfterB() throws {
        let directory = try makeFixtureDirectory(name: "PerType")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = makeBinarySuggestion(template: "associativity", funcName: "merge")
        let second = makeBinarySuggestion(template: "identity-element", funcName: "merge")
        let proposal = RefactorBridgeProposal(
            typeName: "IntSet",
            protocolName: "Monoid",
            combineWitness: "merge",
            identityWitness: "empty",
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            relatedIdentities: [first.identity, second.identity]
        )
        let output = TriageRecordingOutput()
        // First prompt: B (accept conformance). Second prompt: should
        // collapse to [A/s/n/?]; user types s. If the prompt doesn't
        // collapse, the next line would be `[A/B/s/n/?]` and the test
        // assertion below catches it.
        _ = try InteractiveTriage.run(
            suggestions: [first, second],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["B", "s"]),
                output: output,
                outputDirectory: directory,
                proposalsByType: ["IntSet": proposal]
            )
        )
        let promptLines = output.lines.filter { $0.contains("/2]") }
        #expect(promptLines.count == 2)
        #expect(promptLines[0].contains("Conformance (B)"))
        #expect(promptLines[1].contains("Conformance (B)") == false)
    }

    // MARK: - Proposal not attached

    @Test("Suggestion whose identity is NOT in relatedIdentities sees only [A/s/n/?]")
    func proposalDoesNotShowForUnrelatedSuggestion() throws {
        let directory = try makeFixtureDirectory(name: "Unrelated")
        defer { try? FileManager.default.removeItem(at: directory) }
        let assoc = makeBinarySuggestion(template: "associativity", funcName: "merge")
        let unrelated = makeBinarySuggestion(template: "commutativity", funcName: "swap")
        let proposal = RefactorBridgeProposal(
            typeName: "IntSet",
            protocolName: "Semigroup",
            combineWitness: "merge",
            identityWitness: nil,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            relatedIdentities: [assoc.identity]  // unrelated.identity NOT in set
        )
        let output = TriageRecordingOutput()
        _ = try InteractiveTriage.run(
            suggestions: [unrelated],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["s"]),
                output: output,
                outputDirectory: directory,
                proposalsByType: ["IntSet": proposal]
            )
        )
        let promptLines = output.lines.filter { $0.contains("/1]") }
        #expect(promptLines.first?.contains("Conformance (B)") == false)
    }

    // MARK: - Dry-run

    @Test("B accept under --dry-run logs the would-be path but writes no file")
    func bAcceptDryRunSkipsFileWrite() throws {
        let directory = try makeFixtureDirectory(name: "BDryRun")
        defer { try? FileManager.default.removeItem(at: directory) }
        let assoc = makeBinarySuggestion(template: "associativity", funcName: "merge")
        let proposal = RefactorBridgeProposal(
            typeName: "IntSet",
            protocolName: "Semigroup",
            combineWitness: "merge",
            identityWitness: nil,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            relatedIdentities: [assoc.identity]
        )
        let output = TriageRecordingOutput()
        let result = try InteractiveTriage.run(
            suggestions: [assoc],
            existingDecisions: .empty,
            context: makeContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["B"]),
                output: output,
                outputDirectory: directory,
                dryRun: true,
                proposalsByType: ["IntSet": proposal]
            )
        )
        #expect(result.writtenFiles.isEmpty)
        // Decisions also not updated under dry-run (matches A-arm behaviour).
        #expect(result.updatedDecisions == .empty)
        #expect(output.lines.contains { $0.contains("[dry-run] would write") })
    }

    // MARK: - Helpers

    private func makeContext(
        prompt: TriageRecordingPromptInput,
        output: TriageRecordingOutput = TriageRecordingOutput(),
        diagnostics: TriageRecordingDiagnosticOutput = TriageRecordingDiagnosticOutput(),
        outputDirectory: URL,
        dryRun: Bool = false,
        proposalsByType: [String: RefactorBridgeProposal] = [:]
    ) -> InteractiveTriage.Context {
        InteractiveTriage.Context(
            prompt: prompt,
            output: output,
            diagnostics: diagnostics,
            outputDirectory: outputDirectory,
            dryRun: dryRun,
            clock: { Date(timeIntervalSince1970: 0) },
            proposalsByType: proposalsByType
        )
    }

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("RBTriageTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
