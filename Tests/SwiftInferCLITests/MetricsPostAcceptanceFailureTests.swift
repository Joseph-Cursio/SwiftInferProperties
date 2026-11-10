import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// V1.72.C — PRD §17.2's 5th and final metric: post-acceptance failure
// rate. Joins accepted decisions against post-acceptance outcomes by
// identity hash and computes `nowFails / (stillPasses + nowFails)`
// per template. `obsolete` and `error` outcomes are shown in counts
// but excluded from the rate denominator.

@Suite("MetricsRenderer — V1.72.C post-acceptance failure rate (§17.2 5/5)")
struct MetricsPostAcceptanceFailureTests {

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func decision(
        identity: String,
        template: String = "round-trip",
        choice: Decision = .accepted
    ) throws -> DecisionRecord {
        DecisionRecord(
            identityHash: identity,
            template: template,
            scoreAtDecision: 80,
            tier: .strong,
            decision: choice,
            timestamp: try date("2026-05-14T10:00:00Z")
        )
    }

    private func outcome(
        identity: String,
        template: String = "round-trip",
        kind: PostAcceptanceOutcomeKind
    ) throws -> PostAcceptanceOutcome {
        PostAcceptanceOutcome(
            identityHash: identity,
            template: template,
            outcome: kind,
            detail: nil,
            originalAcceptedAt: try date("2026-05-14T10:00:00Z"),
            checkedAt: try date("2026-05-15T10:00:00Z"),
            swiftInferVersion: "1.72.0"
        )
    }

    // MARK: - postAcceptanceFailureRows

    @Test("joins accepted decisions to outcomes and aggregates per-template counts")
    func joinAndAggregate() throws {
        let decisions = Decisions(records: [
            try decision(identity: "AAA1111111111111"),
            try decision(identity: "BBB2222222222222"),
            try decision(identity: "CCC3333333333333"),
            try decision(identity: "DDD4444444444444"),
        ])
        let outcomes = PostAcceptanceOutcomeLog(records: [
            try outcome(identity: "AAA1111111111111", kind: .stillPasses),
            try outcome(identity: "BBB2222222222222", kind: .stillPasses),
            try outcome(identity: "CCC3333333333333", kind: .nowFails),
            try outcome(identity: "DDD4444444444444", kind: .obsolete),
        ])
        let rows = MetricsRenderer.postAcceptanceFailureRows(decisions: decisions, outcomes: outcomes)
        #expect(rows.count == 1)
        let row = rows[0]
        #expect(row.template == "round-trip")
        #expect(row.stillPasses == 2)
        #expect(row.nowFails == 1)
        #expect(row.obsolete == 1)
        #expect(row.error == 0)
        // 1 fail / (2 pass + 1 fail) = 1/3 ≈ 0.333
        #expect(row.failureRate != nil)
        #expect(abs((row.failureRate ?? 0) - (1.0 / 3.0)) < 1e-9)
    }

    @Test("obsolete and error outcomes do not contribute to the rate denominator")
    func obsoleteAndErrorExcludedFromRate() throws {
        let decisions = Decisions(records: [
            try decision(identity: "AAA1111111111111"),
            try decision(identity: "BBB2222222222222"),
            try decision(identity: "CCC3333333333333"),
            try decision(identity: "DDD4444444444444"),
        ])
        let outcomes = PostAcceptanceOutcomeLog(records: [
            try outcome(identity: "AAA1111111111111", kind: .stillPasses),
            try outcome(identity: "BBB2222222222222", kind: .nowFails),
            try outcome(identity: "CCC3333333333333", kind: .obsolete),
            try outcome(identity: "DDD4444444444444", kind: .error),
        ])
        let rows = MetricsRenderer.postAcceptanceFailureRows(decisions: decisions, outcomes: outcomes)
        #expect(rows[0].failureRate == 0.5) // 1 / (1 + 1)
    }

    @Test("only-obsolete-and-error template yields a nil rate (n/a)")
    func nilRateWhenNoMeasurableRecords() throws {
        let decisions = Decisions(records: [
            try decision(identity: "AAA1111111111111"),
            try decision(identity: "BBB2222222222222"),
        ])
        let outcomes = PostAcceptanceOutcomeLog(records: [
            try outcome(identity: "AAA1111111111111", kind: .obsolete),
            try outcome(identity: "BBB2222222222222", kind: .error),
        ])
        let rows = MetricsRenderer.postAcceptanceFailureRows(decisions: decisions, outcomes: outcomes)
        #expect(rows.count == 1)
        #expect(rows[0].failureRate == nil)
    }

    @Test("rejected and skipped decisions do not contribute even when they have a matching outcome")
    func onlyAccepted() throws {
        let decisions = Decisions(records: [
            try decision(identity: "AAA1111111111111", choice: .rejected),
            try decision(identity: "BBB2222222222222", choice: .skipped),
            try decision(identity: "CCC3333333333333", choice: .acceptedAsConformance),
        ])
        let outcomes = PostAcceptanceOutcomeLog(records: [
            try outcome(identity: "AAA1111111111111", kind: .stillPasses),
            try outcome(identity: "BBB2222222222222", kind: .nowFails),
            try outcome(identity: "CCC3333333333333", kind: .stillPasses),
        ])
        let rows = MetricsRenderer.postAcceptanceFailureRows(decisions: decisions, outcomes: outcomes)
        #expect(rows.count == 1)
        #expect(rows[0].stillPasses == 1)
        #expect(rows[0].nowFails == 0)
    }

    @Test("unmatched outcome (no matching decision) is dropped from the join")
    func unmatchedOutcomeIsDropped() throws {
        let decisions = Decisions(records: [
            try decision(identity: "AAA1111111111111")
        ])
        let outcomes = PostAcceptanceOutcomeLog(records: [
            try outcome(identity: "AAA1111111111111", kind: .stillPasses),
            try outcome(identity: "ZZZ9999999999999", kind: .nowFails), // no decision
        ])
        let rows = MetricsRenderer.postAcceptanceFailureRows(decisions: decisions, outcomes: outcomes)
        #expect(rows[0].stillPasses == 1)
        #expect(rows[0].nowFails == 0)
    }

    @Test("rows sort by total descending then template ascending")
    func rowsSort() throws {
        let decisions = Decisions(records: [
            try decision(identity: "AAA1111111111111", template: "idempotence"),
            try decision(identity: "BBB2222222222222", template: "round-trip"),
            try decision(identity: "CCC3333333333333", template: "round-trip"),
            try decision(identity: "DDD4444444444444", template: "commutativity"),
            try decision(identity: "EEE5555555555555", template: "commutativity"),
            try decision(identity: "FFF6666666666666", template: "commutativity"),
        ])
        let outcomes = PostAcceptanceOutcomeLog(records: [
            try outcome(identity: "AAA1111111111111", template: "idempotence", kind: .stillPasses),
            try outcome(identity: "BBB2222222222222", template: "round-trip", kind: .stillPasses),
            try outcome(identity: "CCC3333333333333", template: "round-trip", kind: .nowFails),
            try outcome(identity: "DDD4444444444444", template: "commutativity", kind: .stillPasses),
            try outcome(identity: "EEE5555555555555", template: "commutativity", kind: .nowFails),
            try outcome(identity: "FFF6666666666666", template: "commutativity", kind: .obsolete),
        ])
        let rows = MetricsRenderer.postAcceptanceFailureRows(decisions: decisions, outcomes: outcomes)
        #expect(rows.map(\.template) == ["commutativity", "round-trip", "idempotence"])
    }

    // MARK: - section render

    @Test("section renders sentinel when no outcomes are loaded")
    func sectionSentinelOnEmptyOutcomes() throws {
        let lines = MetricsRenderer.postAcceptanceFailureSection(
            decisions: Decisions(records: [try decision(identity: "AAA1111111111111")]),
            outcomes: .empty
        )
        let rendered = lines.joined(separator: "\n")
        #expect(rendered.contains("Post-acceptance failure rate (PRD §17.2):"))
        #expect(rendered.contains("(no post-acceptance outcomes — run `swift-infer accept-check` to populate)"))
    }

    @Test("section renders alternate sentinel when outcomes exist but none join")
    func sectionSentinelOnUnjoinedOutcomes() throws {
        let lines = MetricsRenderer.postAcceptanceFailureSection(
            decisions: Decisions(records: [try decision(identity: "AAA1111111111111")]),
            outcomes: PostAcceptanceOutcomeLog(records: [
                try outcome(identity: "ZZZ9999999999999", kind: .stillPasses)
            ])
        )
        let rendered = lines.joined(separator: "\n")
        #expect(rendered.contains("(no accepted decisions joined to a post-acceptance outcome)"))
    }

    @Test("section surfaces selection-bias caveat in the header")
    func sectionHasSelectionBiasCaveat() throws {
        let lines = MetricsRenderer.postAcceptanceFailureSection(
            decisions: Decisions(records: [try decision(identity: "AAA1111111111111")]),
            outcomes: PostAcceptanceOutcomeLog(records: [
                try outcome(identity: "AAA1111111111111", kind: .stillPasses)
            ])
        )
        let rendered = lines.joined(separator: "\n")
        #expect(rendered.contains("selection bias applies"))
    }

    @Test("section names the obsolete-excluded count when obsolete records exist")
    func sectionNamesObsoleteCount() throws {
        let lines = MetricsRenderer.postAcceptanceFailureSection(
            decisions: Decisions(records: [
                try decision(identity: "AAA1111111111111"),
                try decision(identity: "BBB2222222222222"),
            ]),
            outcomes: PostAcceptanceOutcomeLog(records: [
                try outcome(identity: "AAA1111111111111", kind: .stillPasses),
                try outcome(identity: "BBB2222222222222", kind: .obsolete),
            ])
        )
        let rendered = lines.joined(separator: "\n")
        #expect(rendered.contains("1 `obsolete` record excluded from the rate denominator"))
    }

    @Test("section omits the obsolete caveat when there are zero obsolete records")
    func sectionOmitsObsoleteCaveatWhenZero() throws {
        let lines = MetricsRenderer.postAcceptanceFailureSection(
            decisions: Decisions(records: [try decision(identity: "AAA1111111111111")]),
            outcomes: PostAcceptanceOutcomeLog(records: [
                try outcome(identity: "AAA1111111111111", kind: .stillPasses)
            ])
        )
        let rendered = lines.joined(separator: "\n")
        #expect(!rendered.contains("obsolete"))
    }

    @Test("populated section renders a table with one row per template")
    func sectionRendersTable() throws {
        let lines = MetricsRenderer.postAcceptanceFailureSection(
            decisions: Decisions(records: [
                try decision(identity: "AAA1111111111111"),
                try decision(identity: "BBB2222222222222"),
            ]),
            outcomes: PostAcceptanceOutcomeLog(records: [
                try outcome(identity: "AAA1111111111111", kind: .stillPasses),
                try outcome(identity: "BBB2222222222222", kind: .nowFails),
            ])
        )
        let rendered = lines.joined(separator: "\n")
        #expect(rendered.contains("| Template               | Passes | Fails | Obsolete | Error |   Rate |"))
        #expect(rendered.contains("| round-trip"))
        #expect(rendered.contains("50.0%"))
    }

    @Test("section renders 'n/a' for templates with no measurable records")
    func sectionRendersNaRate() throws {
        let lines = MetricsRenderer.postAcceptanceFailureSection(
            decisions: Decisions(records: [try decision(identity: "AAA1111111111111")]),
            outcomes: PostAcceptanceOutcomeLog(records: [
                try outcome(identity: "AAA1111111111111", kind: .error)
            ])
        )
        let rendered = lines.joined(separator: "\n")
        #expect(rendered.contains("n/a"))
    }

    // MARK: - formatFailureRate

    @Test
    func formatFailureRateFormatsAsPercent() {
        #expect(MetricsRenderer.formatFailureRate(0.5) == "50.0%")
        #expect(MetricsRenderer.formatFailureRate(0.0) == "0.0%")
        #expect(MetricsRenderer.formatFailureRate(1.0) == "100.0%")
    }

    @Test
    func formatFailureRateRendersNaForNilRate() {
        #expect(MetricsRenderer.formatFailureRate(nil) == "n/a")
    }
}
