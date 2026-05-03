import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M6.2 acceptance — `.swiftinfer/decisions.json`
/// persistence works for lifted suggestions the same way it works
/// for TemplateEngine-side suggestions. Pure regression coverage —
/// the existing `InteractiveTriage.run` flow already filters by
/// `existingDecisions.record(for: identity.normalized) == nil`
/// regardless of TE-vs-lifted origin (M5.5's
/// `lifted|<template>|<calleeNames>` identity scheme produces
/// normalized hashes the same way), so M6.2 pins the contract for
/// the lifted side rather than adding new behavior.
///
/// Uses count-invariance for the same reason `LiftedSkipMarkerHonoringTests`
/// does — `InvariantPreservationTemplate` is annotation-only on
/// the TE side, so the lifted enters the visible stream lifted-only
/// and the test exercises the lifted-side persistence path cleanly.
@Suite("Discover — decisions.json persistence for lifted suggestions (M6.2)")
struct LiftedDecisionsPersistenceTests {

    @Test("Accept gesture on a lifted suggestion writes a DecisionRecord with the lifted identity")
    func acceptWritesLiftedDecisionRecord() throws {
        let directory = try makeFixture(name: "AcceptLifted")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try writeSourcesUnannotatedFilter(in: directory)
        try writeTestsCountInvariantBody(in: directory)

        let lifted = try discoverLifted(directory: directory)
        let outcome = try runInteractive(
            suggestion: lifted,
            existingDecisions: .empty,
            outputDirectory: directory,
            scriptedInput: "A"
        )
        let record = try #require(
            outcome.updatedDecisions.record(for: lifted.identity.normalized)
        )
        #expect(record.template == "invariant-preservation")
        #expect(record.decision == .accepted)
    }

    @Test("Subsequent run filters out the previously-accepted lifted suggestion")
    func acceptedLiftedSuggestionIsFilteredOnNextRun() throws {
        let directory = try makeFixture(name: "AcceptThenRerun")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try writeSourcesUnannotatedFilter(in: directory)
        try writeTestsCountInvariantBody(in: directory)

        let lifted = try discoverLifted(directory: directory)
        let priorDecisions = Decisions(records: [
            DecisionRecord(
                identityHash: lifted.identity.normalized,
                template: "invariant-preservation",
                scoreAtDecision: lifted.score.total,
                tier: lifted.score.tier,
                decision: .accepted,
                timestamp: Date(timeIntervalSince1970: 0),
                signalWeights: lifted.score.signals.map {
                    SignalSnapshot(kind: $0.kind.rawValue, weight: $0.weight)
                }
            )
        ])
        let outcome = try runInteractive(
            suggestion: lifted,
            existingDecisions: priorDecisions,
            outputDirectory: directory,
            scriptedInput: ""
        )
        // No new decision recorded — the prior decision pinned
        // `existingDecisions.record(for:)`, so InteractiveTriage's
        // `pending` filter dropped this lifted before the prompt loop.
        #expect(
            outcome.updatedDecisions == priorDecisions,
            "Decisions should pass through unchanged when the lifted is already-decided"
        )
        // No file written either.
        #expect(outcome.writtenFiles.isEmpty)
    }

    @Test("Reject gesture on a lifted suggestion writes a .reject DecisionRecord")
    func rejectWritesLiftedDecisionRecord() throws {
        let directory = try makeFixture(name: "RejectLifted")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try writeSourcesUnannotatedFilter(in: directory)
        try writeTestsCountInvariantBody(in: directory)

        let lifted = try discoverLifted(directory: directory)
        let outcome = try runInteractive(
            suggestion: lifted,
            existingDecisions: .empty,
            outputDirectory: directory,
            scriptedInput: "n"
        )
        let record = try #require(
            outcome.updatedDecisions.record(for: lifted.identity.normalized)
        )
        #expect(record.template == "invariant-preservation")
        #expect(record.decision == .rejected)
        // No file written for reject.
        #expect(outcome.writtenFiles.isEmpty)
    }

    @Test("Skip gesture on a lifted suggestion writes a .skip DecisionRecord")
    func skipWritesLiftedDecisionRecord() throws {
        let directory = try makeFixture(name: "SkipLifted")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try writeSourcesUnannotatedFilter(in: directory)
        try writeTestsCountInvariantBody(in: directory)

        let lifted = try discoverLifted(directory: directory)
        let outcome = try runInteractive(
            suggestion: lifted,
            existingDecisions: .empty,
            outputDirectory: directory,
            scriptedInput: "s"
        )
        let record = try #require(
            outcome.updatedDecisions.record(for: lifted.identity.normalized)
        )
        #expect(record.template == "invariant-preservation")
        #expect(record.decision == .skipped)
        #expect(outcome.writtenFiles.isEmpty)
    }

    // MARK: - Fixture helpers

    private func makeFixture(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiftedDecisionsPersistence-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writePackageManifest(in directory: URL) throws {
        try "// swift-tools-version: 5.9\nimport PackageDescription\n"
            .write(
                to: directory.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8
            )
    }

    private func writeSourcesUnannotatedFilter(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources/Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public func filter(_ xs: [Int]) -> [Int] {
            return xs
        }
        """.write(
            to: sources.appendingPathComponent("Filter.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsCountInvariantBody(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests/FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class FilterTests: XCTestCase {
            func testFilterPreservesCount() {
                let xs = [1, 2, 3, 4]
                XCTAssertEqual(filter(xs).count, xs.count)
            }
        }
        """.write(
            to: tests.appendingPathComponent("FilterTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func discoverLifted(directory: URL) throws -> Suggestion {
        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory.appendingPathComponent("Sources/Foo"),
            includePossible: true,
            diagnostics: HGSilentDiagnosticOutput()
        )
        return try #require(result.suggestions.first { suggestion in
            suggestion.liftedOrigin != nil && suggestion.templateName == "invariant-preservation"
        })
    }

    private func runInteractive(
        suggestion: Suggestion,
        existingDecisions: Decisions,
        outputDirectory: URL,
        scriptedInput: String
    ) throws -> InteractiveTriage.Result {
        let lines = scriptedInput.isEmpty ? [] : [scriptedInput]
        let context = InteractiveTriage.Context(
            prompt: HGScriptedPromptInput(scriptedLines: lines),
            output: HGSilentOutput(),
            diagnostics: HGSilentDiagnosticOutput(),
            outputDirectory: outputDirectory,
            dryRun: false
        )
        return try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: existingDecisions,
            context: context
        )
    }
}
