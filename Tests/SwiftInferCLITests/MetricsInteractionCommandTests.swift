import ArgumentParser
import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Covers the `metrics-interaction` command's own glue — the parts the
/// renderer/aggregator/merge unit tests don't reach: `--format` parsing
/// and the default-vs-aggregation load dispatch. Mirrors v1's
/// `MetricsExplicitDecisionsEvidenceTests`, which drives `Metrics.loadAggregate`
/// directly.
@Suite("metrics-interaction — format parse + load dispatch")
struct MetricsInteractionCommandTests {

    private typealias Command = SwiftInferCommand.MetricsInteraction

    // MARK: - --format parsing

    @Test("valid --format values parse to the matching Format case")
    func validFormatsParse() throws {
        #expect(try Command.parseFormat("markdown") == .markdown)
        #expect(try Command.parseFormat("plain") == .plain)
    }

    @Test("--format is case-insensitive")
    func formatIsCaseInsensitive() throws {
        #expect(try Command.parseFormat("MARKDOWN") == .markdown)
        #expect(try Command.parseFormat("Plain") == .plain)
    }

    @Test("an unknown --format value throws ValidationError")
    func unknownFormatThrows() {
        #expect(throws: ValidationError.self) {
            _ = try Command.parseFormat("bogus")
        }
    }

    // MARK: - Load dispatch

    @Test("no --decisions paths → default walk-up path (single package-root source)")
    func emptyPathsDispatchesToDefault() {
        // A directory with no package root and no decisions file: the default
        // path still returns exactly one source label and empty decisions,
        // proving dispatch chose walk-up (not aggregation, which would echo
        // the supplied paths as sources).
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetricsInteractionDefault-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let loaded = Command.loadDecisions(
            directoryOverride: scratch.path,
            explicitPaths: []
        )
        #expect(loaded.sources.count == 1)
        #expect(loaded.sources.first == "(no package root)")
        #expect(loaded.decisions.records.isEmpty)
    }

    @Test("explicit --decisions paths → aggregation path (merges every file, sources echo the paths)")
    func explicitPathsDispatchToAggregation() throws {
        let corpusA = try makeCorpus(name: "A", identity: "AAAA111111111111", family: .idempotence)
        let corpusB = try makeCorpus(name: "B", identity: "BBBB222222222222", family: .cardinality)
        defer {
            try? FileManager.default.removeItem(at: corpusA.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: corpusB.deletingLastPathComponent())
        }

        let loaded = Command.loadDecisions(
            directoryOverride: nil,
            explicitPaths: [corpusA.path, corpusB.path]
        )
        // Aggregation merged both files' records and echoed both paths as
        // sources — the fingerprint of the aggregation branch, not walk-up.
        #expect(loaded.decisions.records.count == 2)
        #expect(loaded.sources == [corpusA.standardizedFileURL.path, corpusB.standardizedFileURL.path])
        #expect(loaded.warnings.isEmpty)
    }

    // MARK: - Fixtures

    private func makeCorpus(
        name: String,
        identity: String,
        family: InteractionInvariantFamily
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetricsInteractionCorpus-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("interaction-decisions.json")
        try InteractionDecisionsLoader.write(
            InteractionDecisions(records: [
                InteractionDecisionRecord(
                    identityHash: identity,
                    family: family,
                    scoreAtDecision: 80,
                    tier: .strong,
                    reducerQualifiedName: "Feature.reduce",
                    decision: .accepted,
                    timestamp: Date(timeIntervalSince1970: 0)
                )
            ]),
            to: path
        )
        return path
    }
}
