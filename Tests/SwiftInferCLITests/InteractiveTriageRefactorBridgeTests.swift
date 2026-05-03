import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

@Suite("InteractiveTriage — RefactorBridge prompt + readChoice (M7.5c + M8.4.b.1)")
struct InteractiveTriageBridgePromptTests {

    // MARK: - Prompt rendering

    @Test("Prompt collapses to [A/s/n/?] when no proposal is attached")
    func promptOmitsBWhenNoProposal() {
        let line = InteractiveTriage.promptLine(position: 1, total: 1, primaryAvailable: false)
        #expect(line == "[1/1] Accept (A) / Skip (s) / Reject (n) / Help (?)")
    }

    @Test("Prompt extends to [A/B/s/n/?] when proposal is attached")
    func promptIncludesBWhenProposalAttached() {
        let line = InteractiveTriage.promptLine(position: 2, total: 5, primaryAvailable: true)
        #expect(line == "[2/5] Accept (A) / Conformance (B) / Skip (s) / Reject (n) / Help (?)")
    }

    @Test("Help text mentions B only when proposal is attached")
    func helpTextConditional() {
        let withB = InteractiveTriage.helpText(primaryAvailable: true)
        let withoutB = InteractiveTriage.helpText(primaryAvailable: false)
        #expect(withB.contains("B — accept Option B (RefactorBridge"))
        #expect(withoutB.contains("B —") == false)
    }

    // MARK: - M8.4.b.1 — extended [A/B/B'/s/n/?] prompt

    @Test("Prompt extends to [A/B/B'/s/n/?] when secondary proposal is attached")
    func promptExtendsWithSecondary() {
        let line = InteractiveTriage.promptLine(
            position: 1,
            total: 1,
            primaryAvailable: true,
            secondaryAvailable: true
        )
        #expect(line.contains("Conformance' (B')"))
    }

    @Test("Prompt only shows B' when both primary AND secondary are available")
    func promptDoesNotShowBPrimeWithoutPrimary() {
        // Defensive: if only secondary is true (impossible by current
        // dispatch but worth pinning), prompt doesn't surface B'.
        let lineSecondaryOnly = InteractiveTriage.promptLine(
            position: 1,
            total: 1,
            primaryAvailable: false,
            secondaryAvailable: true
        )
        #expect(lineSecondaryOnly.contains("Conformance' (B')") == false)
    }

    @Test("Help text mentions B' only when secondaryAvailable is true")
    func helpTextMentionsBPrimeOnlyWhenSecondaryAvailable() {
        let withBPrime = InteractiveTriage.helpText(
            primaryAvailable: true,
            secondaryAvailable: true
        )
        let withoutBPrime = InteractiveTriage.helpText(
            primaryAvailable: true,
            secondaryAvailable: false
        )
        #expect(withBPrime.contains("B' — accept the secondary"))
        #expect(withoutBPrime.contains("B' —") == false)
    }

    @Test("`b'` and `c` both return .conformancePrime when secondaryAvailable is true")
    func bPrimeAndCAreEquivalent() {
        let outputBPrime = TriageRecordingOutput()
        let promptBPrime = TriageRecordingPromptInput(scriptedLines: ["b'"])
        let choiceBPrime = InteractiveTriage.readChoice(
            prompt: promptBPrime,
            output: outputBPrime,
            primaryAvailable: true,
            secondaryAvailable: true
        )
        switch choiceBPrime {
        case .conformancePrime: break
        default: Issue.record("expected .conformancePrime for b', got \(choiceBPrime)")
        }

        let outputC = TriageRecordingOutput()
        let promptC = TriageRecordingPromptInput(scriptedLines: ["c"])
        let choiceC = InteractiveTriage.readChoice(
            prompt: promptC,
            output: outputC,
            primaryAvailable: true,
            secondaryAvailable: true
        )
        switch choiceC {
        case .conformancePrime: break
        default: Issue.record("expected .conformancePrime for c, got \(choiceC)")
        }
    }

    @Test("`b'` is rejected when secondaryAvailable is false")
    func bPrimeRequiresSecondaryAvailable() {
        let output = TriageRecordingOutput()
        let prompt = TriageRecordingPromptInput(scriptedLines: ["b'", "s"])
        let choice = InteractiveTriage.readChoice(
            prompt: prompt,
            output: output,
            primaryAvailable: true,
            secondaryAvailable: false
        )
        switch choice {
        case .skip: break
        default: Issue.record("expected .skip fallthrough, got \(choice)")
        }
        #expect(output.lines.contains { $0.contains("Unrecognized input 'b''") })
    }

    @Test("`b` is recognized only when primaryAvailable is true")
    func bRequiresProposalAvailable() {
        let outputWithProposal = TriageRecordingOutput()
        let promptWithProposal = TriageRecordingPromptInput(scriptedLines: ["b"])
        let choiceWith = InteractiveTriage.readChoice(
            prompt: promptWithProposal,
            output: outputWithProposal,
            primaryAvailable: true
        )
        switch choiceWith {
        case .conformance: break
        default: Issue.record("expected .conformance when proposal available, got \(choiceWith)")
        }

        let outputWithout = TriageRecordingOutput()
        let promptWithout = TriageRecordingPromptInput(scriptedLines: ["b", "s"])
        let choiceWithout = InteractiveTriage.readChoice(
            prompt: promptWithout,
            output: outputWithout,
            primaryAvailable: false
        )
        switch choiceWithout {
        case .skip: break
        default: Issue.record("expected fallthrough to .skip when no proposal, got \(choiceWithout)")
        }
        #expect(outputWithout.lines.contains { $0.contains("Unrecognized input 'b'") })
    }
}

@Suite("InteractiveTriage — RefactorBridge B accept end-to-end (M7.5c)")
struct InteractiveTriageBridgeAcceptTests {

    @Test("B accept writes a Semigroup conformance file and records .acceptedAsConformance")
    func bAcceptWritesSemigroupExtension() throws {
        let directory = try makeRBFixtureDirectory(name: "BAcceptSemigroup")
        defer { try? FileManager.default.removeItem(at: directory) }
        let assoc = makeBinarySuggestion(template: "associativity", funcName: "merge")
        let proposal = RefactorBridgeProposal(
            typeName: "IntSet",
            protocolName: "Semigroup",
            combineWitness: "merge",
            identityWitness: nil,
            explainability: ExplainabilityBlock(
                whySuggested: ["op match"],
                whyMightBeWrong: ["assoc not verified"]
            ),
            relatedIdentities: [assoc.identity]
        )
        let result = try InteractiveTriage.run(
            suggestions: [assoc],
            existingDecisions: .empty,
            context: makeRBContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["B"]),
                outputDirectory: directory,
                proposalsByType: ["IntSet": [proposal]]
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
        let directory = try makeRBFixtureDirectory(name: "BAcceptMonoid")
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
            context: makeRBContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["B"]),
                outputDirectory: directory,
                proposalsByType: ["IntSet": [proposal]]
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

    @Test("Once user picks B for type T, subsequent suggestions on T collapse to [A/s/n/?]")
    func perTypeAggregationCollapsesPromptAfterB() throws {
        let directory = try makeRBFixtureDirectory(name: "PerType")
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
        _ = try InteractiveTriage.run(
            suggestions: [first, second],
            existingDecisions: .empty,
            context: makeRBContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["B", "s"]),
                output: output,
                outputDirectory: directory,
                proposalsByType: ["IntSet": [proposal]]
            )
        )
        let promptLines = output.lines.filter { $0.contains("/2]") }
        #expect(promptLines.count == 2)
        #expect(promptLines[0].contains("Conformance (B)"))
        #expect(promptLines[1].contains("Conformance (B)") == false)
    }

    @Test("Suggestion whose identity is NOT in relatedIdentities sees only [A/s/n/?]")
    func proposalDoesNotShowForUnrelatedSuggestion() throws {
        let directory = try makeRBFixtureDirectory(name: "Unrelated")
        defer { try? FileManager.default.removeItem(at: directory) }
        let assoc = makeBinarySuggestion(template: "associativity", funcName: "merge")
        let unrelated = makeBinarySuggestion(template: "commutativity", funcName: "swap")
        let proposal = RefactorBridgeProposal(
            typeName: "IntSet",
            protocolName: "Semigroup",
            combineWitness: "merge",
            identityWitness: nil,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            relatedIdentities: [assoc.identity]
        )
        let output = TriageRecordingOutput()
        _ = try InteractiveTriage.run(
            suggestions: [unrelated],
            existingDecisions: .empty,
            context: makeRBContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["s"]),
                output: output,
                outputDirectory: directory,
                proposalsByType: ["IntSet": [proposal]]
            )
        )
        let promptLines = output.lines.filter { $0.contains("/1]") }
        #expect(promptLines.first?.contains("Conformance (B)") == false)
    }

    @Test("B accept under --dry-run logs the would-be path but writes no file")
    func bAcceptDryRunSkipsFileWrite() throws {
        let directory = try makeRBFixtureDirectory(name: "BDryRun")
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
            context: makeRBContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["B"]),
                output: output,
                outputDirectory: directory,
                dryRun: true,
                proposalsByType: ["IntSet": [proposal]]
            )
        )
        #expect(result.writtenFiles.isEmpty)
        // Decisions also not updated under dry-run (matches A-arm behaviour).
        #expect(result.updatedDecisions == .empty)
        #expect(output.lines.contains { $0.contains("[dry-run] would write") })
    }
}

// MARK: - Shared helpers

func makeRBContext(
    prompt: TriageRecordingPromptInput,
    output: TriageRecordingOutput = TriageRecordingOutput(),
    diagnostics: TriageRecordingDiagnosticOutput = TriageRecordingDiagnosticOutput(),
    outputDirectory: URL,
    dryRun: Bool = false,
    proposalsByType: [String: [RefactorBridgeProposal]] = [:]
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

func makeRBFixtureDirectory(name: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("RBTriageTests-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}
