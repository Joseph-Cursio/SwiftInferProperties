import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V1.72.A — pure-function tests for the `AcceptCheck` skeleton:
// the verify-outcome classifier, the accepted-records filter, and the
// summary renderer. The verify-subprocess path (`checkOne` calling
// `Verify.runPipeline`) is exercised by `AcceptCheckIntegrationTests`
// once V1.72.B's persistence is in place; this suite stays
// subprocess-free so the fast `swift test` skip-list keeps it.

@Suite("AcceptCheck — V1.72.A classification + render")
struct AcceptCheckCommandTests {

    private typealias Command = SwiftInferCommand.AcceptCheck

    private func decision(
        identity: String,
        template: String = "round-trip",
        choice: Decision = .accepted
    ) -> DecisionRecord {
        DecisionRecord(
            identityHash: identity,
            template: template,
            scoreAtDecision: 80,
            tier: .strong,
            decision: choice,
            timestamp: ISO8601DateFormatter().date(from: "2026-05-14T10:00:00Z")!
        )
    }

    // MARK: - classify

    @Test("bothPass classifies as stillPasses with detail")
    func classifyBothPass() {
        let result = Command.classify(evidence: .measuredBothPass)
        #expect(result.kind == .stillPasses)
        #expect(result.detail == "bothPass")
    }

    @Test("edgeCaseAdvisory also classifies as stillPasses — the post-acceptance question collapses both")
    func classifyEdgeCaseAdvisory() {
        let result = Command.classify(evidence: .measuredEdgeCaseAdvisory)
        #expect(result.kind == .stillPasses)
        #expect(result.detail == "edgeCaseAdvisory")
    }

    @Test("defaultFails classifies as nowFails — the regression signal §17.2 wants")
    func classifyDefaultFails() {
        let result = Command.classify(evidence: .measuredDefaultFails)
        #expect(result.kind == .nowFails)
        #expect(result.detail == "defaultFails")
    }

    @Test("measuredError classifies as error")
    func classifyMeasuredError() {
        let result = Command.classify(evidence: .measuredError)
        #expect(result.kind == .error)
        #expect(result.detail == "verify-error")
    }

    @Test("architecturalCoveragePending classifies as error — not a verdict either way")
    func classifyArchitecturalPending() {
        let result = Command.classify(evidence: .architecturalCoveragePending)
        #expect(result.kind == .error)
        #expect(result.detail == "architectural-coverage-pending")
    }

    // MARK: - acceptedRecords filter

    @Test("filters to accepted and acceptedAsConformance; drops rejected and skipped")
    func acceptedRecordsKeepsAcceptsOnly() {
        let decisions = Decisions(records: [
            decision(identity: "AAA1111111111111", choice: .accepted),
            decision(identity: "BBB2222222222222", choice: .acceptedAsConformance),
            decision(identity: "CCC3333333333333", choice: .rejected),
            decision(identity: "DDD4444444444444", choice: .skipped)
        ])
        let kept = Command.acceptedRecords(from: decisions, templateFilter: nil)
        #expect(kept.map(\.identityHash) == ["AAA1111111111111", "BBB2222222222222"])
    }

    @Test("template filter narrows to matching template")
    func acceptedRecordsTemplateFilter() {
        let decisions = Decisions(records: [
            decision(identity: "AAA1111111111111", template: "round-trip"),
            decision(identity: "BBB2222222222222", template: "idempotence"),
            decision(identity: "CCC3333333333333", template: "round-trip")
        ])
        let kept = Command.acceptedRecords(from: decisions, templateFilter: "round-trip")
        #expect(kept.map(\.identityHash) == ["AAA1111111111111", "CCC3333333333333"])
    }

    @Test("empty decisions yields empty filter result")
    func acceptedRecordsEmpty() {
        let kept = Command.acceptedRecords(from: .empty, templateFilter: nil)
        #expect(kept.isEmpty)
    }

    // MARK: - renderSummary

    @Test("empty results renders a single 'no accepted decisions' line")
    func renderEmpty() {
        let rendered = Command.renderSummary(results: [])
        #expect(rendered == "swift-infer accept-check: no accepted decisions to re-check.\n")
    }

    @Test("singular vs plural decision count in the header")
    func renderHeaderPluralization() {
        let singular = Command.renderSummary(results: [
            AcceptCheckResult(record: decision(identity: "AAA1111111111111"), kind: .stillPasses, detail: "bothPass")
        ])
        #expect(singular.contains("re-verified 1 accepted decision:"))
        let plural = Command.renderSummary(results: [
            AcceptCheckResult(record: decision(identity: "AAA1111111111111"), kind: .stillPasses, detail: "bothPass"),
            AcceptCheckResult(record: decision(identity: "BBB2222222222222"), kind: .nowFails, detail: "defaultFails")
        ])
        #expect(plural.contains("re-verified 2 accepted decisions:"))
    }

    @Test("per-record line carries identity, template, kind, and detail")
    func renderPerRecordLine() {
        let rendered = Command.renderSummary(results: [
            AcceptCheckResult(
                record: decision(identity: "AAA1111111111111", template: "round-trip"),
                kind: .stillPasses,
                detail: "bothPass"
            )
        ])
        #expect(rendered.contains("AAA1111111111111  round-trip  still-passes (bothPass)"))
    }

    @Test("per-record line omits the parenthetical when detail is nil")
    func renderPerRecordLineNoDetail() {
        let rendered = Command.renderSummary(results: [
            AcceptCheckResult(
                record: decision(identity: "AAA1111111111111", template: "round-trip"),
                kind: .obsolete,
                detail: nil
            )
        ])
        #expect(rendered.contains("AAA1111111111111  round-trip  obsolete\n"))
        #expect(!rendered.contains("obsolete ("))
    }

    @Test("summary block tallies all four kinds even when count is zero")
    func renderSummaryBlockCoversAllKinds() {
        let rendered = Command.renderSummary(results: [
            AcceptCheckResult(record: decision(identity: "AAA1111111111111"), kind: .stillPasses, detail: nil),
            AcceptCheckResult(record: decision(identity: "BBB2222222222222"), kind: .nowFails, detail: nil)
        ])
        #expect(rendered.contains("Summary:"))
        #expect(rendered.contains("still-passes: 1"))
        #expect(rendered.contains("now-fails: 1"))
        #expect(rendered.contains("obsolete: 0"))
        #expect(rendered.contains("error: 0"))
    }

    // MARK: - persist (V1.72.B)

    @Test("persist writes a new record to .swiftinfer/post-acceptance-outcomes.json")
    func persistWritesNewRecord() throws {
        let directory = try makePackageFixture(name: "PersistNew")
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = decision(identity: "AAA1111111111111", template: "round-trip", choice: .accepted)
        let warnings = Command.persist(
            record: record,
            outcome: (.stillPasses, "bothPass"),
            packageRoot: directory,
            now: ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!
        )
        #expect(warnings.isEmpty)

        let path = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("post-acceptance-outcomes.json")
        #expect(FileManager.default.fileExists(atPath: path.path))

        let log = PostAcceptanceOutcomesStore.load(startingFrom: directory).log
        #expect(log.records.count == 1)
        let persisted = log.records[0]
        #expect(persisted.identityHash == "AAA1111111111111")
        #expect(persisted.template == "round-trip")
        #expect(persisted.outcome == .stillPasses)
        #expect(persisted.detail == "bothPass")
        #expect(persisted.originalAcceptedAt == record.timestamp)
    }

    @Test("persist upserts an existing record — the latest verdict wins")
    func persistUpsertsExistingRecord() throws {
        let directory = try makePackageFixture(name: "PersistUpsert")
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = decision(identity: "AAA1111111111111", template: "round-trip")
        _ = Command.persist(
            record: record,
            outcome: (.stillPasses, "bothPass"),
            packageRoot: directory
        )
        // Second run on the same identity flips to nowFails — the
        // accepted property regressed.
        _ = Command.persist(
            record: record,
            outcome: (.nowFails, "defaultFails"),
            packageRoot: directory
        )
        let log = PostAcceptanceOutcomesStore.load(startingFrom: directory).log
        #expect(log.records.count == 1)
        #expect(log.records[0].outcome == .nowFails)
        #expect(log.records[0].detail == "defaultFails")
    }

    @Test("persist preserves prior records for other identity hashes")
    func persistPreservesPriorRecordsForOtherIdentities() throws {
        let directory = try makePackageFixture(name: "PersistPreserve")
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = Command.persist(
            record: decision(identity: "AAA1111111111111"),
            outcome: (.stillPasses, nil),
            packageRoot: directory
        )
        _ = Command.persist(
            record: decision(identity: "BBB2222222222222"),
            outcome: (.nowFails, nil),
            packageRoot: directory
        )
        let log = PostAcceptanceOutcomesStore.load(startingFrom: directory).log
        #expect(log.records.count == 2)
        #expect(Set(log.records.map(\.identityHash)) == ["AAA1111111111111", "BBB2222222222222"])
    }

    // MARK: - Helpers

    /// Fixture directory with a stub `Package.swift` so the
    /// loader walk-up stops at this directory rather than walking
    /// further to the real `SwiftInferProperties/Package.swift`.
    private func makePackageFixture(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcceptCheckCommandTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: base.appendingPathComponent("Package.swift"))
        return base
    }
}
