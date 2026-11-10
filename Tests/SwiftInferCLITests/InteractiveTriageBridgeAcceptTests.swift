import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// MARK: - Shared helpers

func makeRBContext(
    prompt: TriageRecordingPromptInput,
    outputDirectory: URL,
    output: TriageRecordingOutput = TriageRecordingOutput(),
    diagnostics: TriageRecordingDiagnosticOutput = TriageRecordingDiagnosticOutput(),
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
        #expect(contents.contains("import PropertyLawKit"))
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
                outputDirectory: directory,
                output: output,
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
                outputDirectory: directory,
                output: output,
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
                outputDirectory: directory,
                output: output,
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
