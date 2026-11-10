import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.69 — `metrics --decisions <path>...` now joins each corpus's
/// sibling `verify-evidence.json` into the §17.2 cross-reference.
/// Drives `loadAggregate` directly with on-disk corpus fixtures (the
/// `loadExplicitPaths` path was previously untested end-to-end).
@Suite("Metrics --decisions — V1.69 per-corpus verify-evidence join")
struct MetricsExplicitDecisionsEvidenceTests {

    private func makeCorpus(
        name: String,
        identity: String,
        decision: Decision,
        outcome: VerifyEvidenceOutcome?
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetricsCorpus-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let decisionsPath = directory.appendingPathComponent("decisions.json")
        try DecisionsLoader.write(
            Decisions(records: [
                DecisionRecord(
                    identityHash: identity,
                    template: "round-trip",
                    scoreAtDecision: 80,
                    tier: .strong,
                    decision: decision,
                    timestamp: Date(timeIntervalSince1970: 0)
                ),
            ]),
            to: decisionsPath
        )
        if let outcome {
            try VerifyEvidenceStore.write(
                VerifyEvidenceLog(records: [
                    VerifyEvidence(
                        identityHash: identity,
                        template: "round-trip",
                        outcome: outcome,
                        detail: nil,
                        capturedAt: Date(timeIntervalSince1970: 0),
                        swiftInferVersion: "test"
                    ),
                ]),
                to: directory.appendingPathComponent("verify-evidence.json")
            )
        }
        return decisionsPath
    }

    @Test("Each corpus's sibling verify-evidence.json is merged into the cross-reference")
    func siblingEvidenceMergedAcrossCorpora() throws {
        let corpusA = try makeCorpus(
            name: "A", identity: "AAA1111111111111",
            decision: .accepted, outcome: .measuredBothPass
        )
        let corpusB = try makeCorpus(
            name: "B", identity: "BBB2222222222222",
            decision: .rejected, outcome: .measuredDefaultFails
        )
        defer {
            try? FileManager.default.removeItem(at: corpusA.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: corpusB.deletingLastPathComponent())
        }
        let result = SwiftInferCommand.Metrics.loadAggregate(
            directoryOverride: nil,
            explicitPaths: [corpusA.path, corpusB.path]
        )
        // Decisions merged from both corpora; evidence merged from both
        // sibling files.
        #expect(result.decisions.records.count == 2)
        #expect(result.evidence.records.count == 2)
        #expect(result.warnings.isEmpty)

        let rendered = MetricsRenderer.render(
            decisions: result.decisions,
            sources: result.sources,
            evidence: result.evidence
        )
        #expect(rendered.contains("Verify-evidence cross-reference"))
        #expect(rendered.contains("2 of 2 decisions have verify evidence."))
        #expect(!rendered.contains("(no verify evidence"))
    }

    @Test("A corpus with decisions but no verify-evidence sibling is skipped silently")
    func missingEvidenceSiblingIsSilent() throws {
        let withEvidence = try makeCorpus(
            name: "WithEv", identity: "AAA1111111111111",
            decision: .accepted, outcome: .measuredBothPass
        )
        let noEvidence = try makeCorpus(
            name: "NoEv", identity: "BBB2222222222222",
            decision: .skipped, outcome: nil
        )
        defer {
            try? FileManager.default.removeItem(at: withEvidence.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: noEvidence.deletingLastPathComponent())
        }
        let result = SwiftInferCommand.Metrics.loadAggregate(
            directoryOverride: nil,
            explicitPaths: [withEvidence.path, noEvidence.path]
        )
        // Only the one corpus with a sibling contributes evidence; the
        // missing sibling produces no warning.
        #expect(result.decisions.records.count == 2)
        #expect(result.evidence.records.count == 1)
        #expect(result.warnings.isEmpty)
    }
}
