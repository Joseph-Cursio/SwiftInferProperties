import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V1.71 — PRD §17.2 time-to-adoption: the gap between a suggestion
// first being surfaced (`SemanticIndexEntry.firstSeenAt`) and the user
// accepting it (`DecisionRecord.timestamp`). Joined by identity hash;
// no `Decisions` schema bump.

@Suite("MetricsRenderer — V1.71 time-to-adoption")
struct MetricsTimeToAdoptionTests {

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func decision(
        identity: String,
        template: String = "round-trip",
        decision: Decision = .accepted,
        at iso: String
    ) -> DecisionRecord {
        DecisionRecord(
            identityHash: identity,
            template: template,
            scoreAtDecision: 80,
            tier: .strong,
            decision: decision,
            timestamp: date(iso)
        )
    }

    /// `identityHash` is the `0x`-prefixed `display` form a real index
    /// carries — the join normalizes it.
    private func entry(
        displayHash: String,
        template: String = "round-trip",
        firstSeenAt: String
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: displayHash,
            templateName: template,
            score: 80,
            tier: "Strong",
            primaryFunctionName: "f(_:)",
            location: "F.swift:1",
            firstSeenAt: firstSeenAt,
            lastSeenAt: firstSeenAt
        )
    }

    // MARK: - timeToAdoptionRows

    @Test("joins accepted decisions to index entries and aggregates min/median/max")
    func joinAndAggregate() {
        let decisions = Decisions(records: [
            decision(identity: "AAA1111111111111", at: "2026-05-14T10:05:00Z"), // 300s
            decision(identity: "BBB2222222222222", at: "2026-05-14T10:15:00Z"), // 900s
            decision(identity: "CCC3333333333333", at: "2026-05-14T10:10:00Z")  // 600s
        ])
        let entries = [
            entry(displayHash: "0xAAA1111111111111", firstSeenAt: "2026-05-14T10:00:00Z"),
            entry(displayHash: "0xBBB2222222222222", firstSeenAt: "2026-05-14T10:00:00Z"),
            entry(displayHash: "0xCCC3333333333333", firstSeenAt: "2026-05-14T10:00:00Z")
        ]
        let rows = MetricsRenderer.timeToAdoptionRows(decisions: decisions, indexEntries: entries)
        #expect(rows.count == 1)
        let row = rows[0]
        #expect(row.template == "round-trip")
        #expect(row.count == 3)
        #expect(row.minSeconds == 300)
        #expect(row.medianSeconds == 600)
        #expect(row.maxSeconds == 900)
    }

    @Test("even count takes the mean of the two central durations")
    func medianEvenCount() {
        let decisions = Decisions(records: [
            decision(identity: "AAA1111111111111", at: "2026-05-14T10:01:00Z"), // 60s
            decision(identity: "BBB2222222222222", at: "2026-05-14T10:05:00Z")  // 300s
        ])
        let entries = [
            entry(displayHash: "0xAAA1111111111111", firstSeenAt: "2026-05-14T10:00:00Z"),
            entry(displayHash: "0xBBB2222222222222", firstSeenAt: "2026-05-14T10:00:00Z")
        ]
        let rows = MetricsRenderer.timeToAdoptionRows(decisions: decisions, indexEntries: entries)
        #expect(rows[0].medianSeconds == 180) // (60 + 300) / 2
    }

    @Test("rejected/skipped decisions and unmatched hashes do not contribute")
    func onlyAcceptedAndJoined() {
        let decisions = Decisions(records: [
            decision(identity: "AAA1111111111111", decision: .rejected, at: "2026-05-14T10:05:00Z"),
            decision(identity: "BBB2222222222222", decision: .skipped, at: "2026-05-14T10:05:00Z"),
            decision(identity: "CCC3333333333333", at: "2026-05-14T10:05:00Z"), // no index entry
            decision(identity: "DDD4444444444444", at: "2026-05-14T10:05:00Z")  // joined
        ])
        let entries = [
            entry(displayHash: "0xAAA1111111111111", firstSeenAt: "2026-05-14T10:00:00Z"),
            entry(displayHash: "0xBBB2222222222222", firstSeenAt: "2026-05-14T10:00:00Z"),
            entry(displayHash: "0xDDD4444444444444", firstSeenAt: "2026-05-14T10:00:00Z")
        ]
        let rows = MetricsRenderer.timeToAdoptionRows(decisions: decisions, indexEntries: entries)
        #expect(rows.count == 1)
        #expect(rows[0].count == 1) // only DDD — accepted AND joined
    }

    @Test("a decision recorded before its first index run clamps to 0")
    func negativeGapClampsToZero() {
        let decisions = Decisions(records: [
            decision(identity: "AAA1111111111111", at: "2026-05-14T09:00:00Z")
        ])
        let entries = [
            entry(displayHash: "0xAAA1111111111111", firstSeenAt: "2026-05-14T10:00:00Z")
        ]
        let rows = MetricsRenderer.timeToAdoptionRows(decisions: decisions, indexEntries: entries)
        #expect(rows[0].maxSeconds == 0)
    }

    // MARK: - formatDuration

    @Test("formatDuration picks the largest whole unit, integer-truncated")
    func durationFormatting() {
        #expect(MetricsRenderer.formatDuration(0) == "0s")
        #expect(MetricsRenderer.formatDuration(45) == "45s")
        #expect(MetricsRenderer.formatDuration(59) == "59s")
        #expect(MetricsRenderer.formatDuration(60) == "1m")
        #expect(MetricsRenderer.formatDuration(3_599) == "59m")
        #expect(MetricsRenderer.formatDuration(3_600) == "1h")
        #expect(MetricsRenderer.formatDuration(86_399) == "23h")
        #expect(MetricsRenderer.formatDuration(86_400) == "1d")
        #expect(MetricsRenderer.formatDuration(259_200) == "3d")
    }

    // MARK: - timeToAdoptionSection rendering

    @Test("section renders the no-index sentinel when no entries are loaded")
    func sectionSentinelNoIndex() {
        let lines = MetricsRenderer.timeToAdoptionSection(decisions: .empty, indexEntries: [])
        #expect(lines.contains("Time-to-adoption (PRD §17.2):"))
        #expect(lines.contains { $0.contains("no SemanticIndex") })
    }

    @Test("section renders the no-join sentinel when the index has no accepted matches")
    func sectionSentinelNoJoin() {
        let decisions = Decisions(records: [
            decision(identity: "AAA1111111111111", decision: .rejected, at: "2026-05-14T10:05:00Z")
        ])
        let entries = [entry(displayHash: "0xAAA1111111111111", firstSeenAt: "2026-05-14T10:00:00Z")]
        let lines = MetricsRenderer.timeToAdoptionSection(decisions: decisions, indexEntries: entries)
        #expect(lines.contains { $0.contains("no accepted decisions joined") })
    }

    @Test("section renders a per-template table when decisions join")
    func sectionRendersTable() {
        let decisions = Decisions(records: [
            decision(identity: "AAA1111111111111", at: "2026-05-14T10:05:00Z")
        ])
        let entries = [entry(displayHash: "0xAAA1111111111111", firstSeenAt: "2026-05-14T10:00:00Z")]
        let lines = MetricsRenderer.timeToAdoptionSection(decisions: decisions, indexEntries: entries)
        #expect(lines.contains { $0.contains("1 accepted decision joined to the index") })
        #expect(lines.contains { $0.contains("| Template") && $0.contains("Median") })
        #expect(lines.contains { $0.contains("round-trip") && $0.contains("5m") })
    }

    @Test("render() includes the time-to-adoption section")
    func renderIncludesSection() {
        let rendered = MetricsRenderer.render(decisions: .empty, sources: ["x"])
        #expect(rendered.contains("Time-to-adoption (PRD §17.2):"))
    }
}

/// V1.71 — `metrics` default + `--decisions` modes load the
/// SemanticIndex (conventional path / sibling `index.json`) for the
/// time-to-adoption join. Drives `loadAggregate` with on-disk fixtures.
@Suite("Metrics --decisions — V1.71 per-corpus index join")
struct MetricsTimeToAdoptionLoadTests {

    private func makeCorpus(name: String, withIndex: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetricsTTA-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try DecisionsLoader.write(
            Decisions(records: [
                DecisionRecord(
                    identityHash: "AAA1111111111111",
                    template: "round-trip",
                    scoreAtDecision: 80,
                    tier: .strong,
                    decision: .accepted,
                    timestamp: ISO8601DateFormatter().date(from: "2026-05-14T10:05:00Z")!
                )
            ]),
            to: directory.appendingPathComponent("decisions.json")
        )
        if withIndex {
            try IndexStore.save(
                IndexStore.Index(
                    updatedAt: "2026-05-14T10:00:00Z",
                    entries: [
                        SemanticIndexEntry(
                            identityHash: "0xAAA1111111111111",
                            templateName: "round-trip",
                            score: 80,
                            tier: "Strong",
                            primaryFunctionName: "f(_:)",
                            location: "F.swift:1",
                            firstSeenAt: "2026-05-14T10:00:00Z",
                            lastSeenAt: "2026-05-14T10:00:00Z"
                        )
                    ]
                ),
                to: directory.appendingPathComponent("index.json")
            )
        }
        return directory.appendingPathComponent("decisions.json")
    }

    @Test("a corpus's sibling index.json joins into the time-to-adoption section")
    func siblingIndexJoins() throws {
        let corpus = try makeCorpus(name: "withIndex", withIndex: true)
        defer { try? FileManager.default.removeItem(at: corpus.deletingLastPathComponent()) }

        let result = SwiftInferCommand.Metrics.loadAggregate(
            directoryOverride: nil,
            explicitPaths: [corpus.path]
        )
        #expect(result.indexEntries.count == 1)
        #expect(result.warnings.isEmpty)

        let rendered = MetricsRenderer.render(
            decisions: result.decisions,
            sources: result.sources,
            evidence: result.evidence,
            indexEntries: result.indexEntries
        )
        #expect(rendered.contains("1 accepted decision joined to the index"))
        #expect(!rendered.contains("(no SemanticIndex"))
    }

    @Test("a corpus with no sibling index.json is skipped silently")
    func missingIndexSiblingIsSilent() throws {
        let corpus = try makeCorpus(name: "noIndex", withIndex: false)
        defer { try? FileManager.default.removeItem(at: corpus.deletingLastPathComponent()) }

        let result = SwiftInferCommand.Metrics.loadAggregate(
            directoryOverride: nil,
            explicitPaths: [corpus.path]
        )
        #expect(result.indexEntries.isEmpty)
        #expect(result.warnings.isEmpty)
    }
}
