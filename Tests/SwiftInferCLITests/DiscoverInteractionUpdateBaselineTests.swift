import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V1.89 — `discover-interaction --update-baseline` write side.
// Symmetric writeout for M10's drift read; the filter is Strong +
// Verified only so the persisted snapshot matches what
// `InteractionDriftDetector` would warn against on the next run.

@Suite("DiscoverInteraction — V1.89 --update-baseline writeout")
struct DiscoverInteractionUpdateBaselineTests {

    private typealias Command = SwiftInferCommand.DiscoverInteraction
    private let firstSeenAt = ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!

    // MARK: - Flag parsing

    @Test("--update-baseline + --dry-run parse correctly")
    func parsesBaselineFlags() throws {
        let parsed = try Command.parse([
            "--target", "MyApp",
            "--update-baseline",
            "--dry-run"
        ])
        #expect(parsed.updateBaseline == true)
        #expect(parsed.dryRun == true)
    }

    @Test("--update-baseline + --dry-run default to false")
    func baselineFlagsDefaultsToFalse() throws {
        let parsed = try Command.parse(["--target", "MyApp"])
        #expect(parsed.updateBaseline == false)
        #expect(parsed.dryRun == false)
    }

    // MARK: - runUpdateBaseline — filter + dry-run + real write

    @Test("runUpdateBaseline filters out non-Strong+ tiers")
    func updateBaselineFiltersTiers() throws {
        let directory = try makeFixtureDirectoryWithPackageManifest(name: "BaselineFilter")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions: [InteractionInvariantSuggestion] = [
            makeSuggestion(tier: .strong, predicate: "state.a == 1"),
            makeSuggestion(tier: .verified, predicate: "state.b == 2"),
            makeSuggestion(tier: .likely, predicate: "state.c == 3"),
            makeSuggestion(tier: .possible, predicate: "state.d == 4"),
            makeSuggestion(tier: .suppressed, predicate: "state.e == 5")
        ]
        let output = UpdateBaselineRecordingOutput()
        try Command.runUpdateBaseline(
            suggestions: suggestions,
            workingDirectory: directory,
            target: "MyApp",
            dryRun: false,
            output: output
        )
        let path = directory.appendingPathComponent(".swiftinfer/interaction-baseline.json")
        let loaded = InteractionBaselineLoader.load(startingFrom: directory)
        #expect(FileManager.default.fileExists(atPath: path.path))
        #expect(loaded.baseline.entries.count == 2)
        let persisted = Set(loaded.baseline.entries.map(\.identityHash))
        let expectedStrong = SuggestionIdentity(canonicalInput:
            InteractionInvariantSuggestion.identityCanonicalInput(
                family: .conservation,
                reducerQualifiedName: "Inbox.body",
                predicate: "state.a == 1"
            )
        ).normalized
        let expectedVerified = SuggestionIdentity(canonicalInput:
            InteractionInvariantSuggestion.identityCanonicalInput(
                family: .conservation,
                reducerQualifiedName: "Inbox.body",
                predicate: "state.b == 2"
            )
        ).normalized
        #expect(persisted == [expectedStrong, expectedVerified])
    }

    @Test("runUpdateBaseline with dry-run reports path and skips write")
    func updateBaselineDryRunSkipsWrite() throws {
        let directory = try makeFixtureDirectoryWithPackageManifest(name: "BaselineDryRun")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = [makeSuggestion(tier: .strong, predicate: "state.x == 1")]
        let output = UpdateBaselineRecordingOutput()
        try Command.runUpdateBaseline(
            suggestions: suggestions,
            workingDirectory: directory,
            target: "MyApp",
            dryRun: true,
            output: output
        )
        let path = directory.appendingPathComponent(".swiftinfer/interaction-baseline.json")
        #expect(!FileManager.default.fileExists(atPath: path.path))
        #expect(output.lines.contains {
            $0.hasPrefix("[dry-run] would write interaction-baseline to ")
        })
        #expect(output.lines.contains { $0.contains("(1 entries).") })
    }

    @Test("runUpdateBaseline real write produces a baseline that round-trips via the loader")
    func updateBaselineWriteRoundTrips() throws {
        let directory = try makeFixtureDirectoryWithPackageManifest(name: "BaselineRoundTrip")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeSuggestion(
            tier: .strong,
            predicate: "state.count == state.items.count",
            family: .conservation
        )
        let output = UpdateBaselineRecordingOutput()
        try Command.runUpdateBaseline(
            suggestions: [suggestion],
            workingDirectory: directory,
            target: "MyApp",
            dryRun: false,
            output: output
        )
        let result = InteractionBaselineLoader.load(startingFrom: directory)
        #expect(result.warnings.isEmpty)
        #expect(result.baseline.entries.count == 1)
        let entry = result.baseline.entries[0]
        #expect(entry.identityHash == suggestion.identity.normalized)
        #expect(entry.family == .conservation)
        #expect(entry.scoreAtSnapshot == suggestion.score)
        #expect(entry.tier == .strong)
        #expect(entry.reducerQualifiedName == "Inbox.body")
        #expect(output.lines.contains { $0.hasPrefix("Wrote interaction-baseline to ") })
    }

    @Test("runUpdateBaseline emits empty entries list when no Strong+ suggestions exist")
    func updateBaselineEmptyWhenNoStrong() throws {
        let directory = try makeFixtureDirectoryWithPackageManifest(name: "BaselineEmpty")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = [
            makeSuggestion(tier: .possible, predicate: "state.a == 1"),
            makeSuggestion(tier: .likely, predicate: "state.b == 2")
        ]
        let output = UpdateBaselineRecordingOutput()
        try Command.runUpdateBaseline(
            suggestions: suggestions,
            workingDirectory: directory,
            target: "MyApp",
            dryRun: false,
            output: output
        )
        let result = InteractionBaselineLoader.load(startingFrom: directory)
        #expect(result.baseline.entries.isEmpty)
        #expect(output.lines.contains { $0.contains("(0 entries).") })
    }

    // MARK: - run() orchestrator — additive (write + render)

    @Test("run() with --update-baseline writes the baseline AND renders the suggestion stream")
    func runAdditiveWriteAndRender() throws {
        let directory = try makeFixtureDirectoryWithPackageManifest(name: "RunAdditive")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Inbox.swift",
            contents: """
            struct Inbox {
                struct State {
                    var count: Int
                    var items: [String]
                }
                enum Action { case other }
                static func reduce(_ s: State, _ a: Action) -> State { return s }
            }
            """
        )
        let output = UpdateBaselineRecordingOutput()
        try Command.run(
            target: "MyApp",
            includePossible: true,
            updateBaseline: true,
            dryRun: false,
            workingDirectory: directory,
            output: output,
            firstSeenAt: firstSeenAt
        )
        let combined = output.lines.joined(separator: "\n")
        #expect(combined.contains("Wrote interaction-baseline to "))
        #expect(combined.contains("Family:    conservation"))
        let baselinePath = directory.appendingPathComponent(".swiftinfer/interaction-baseline.json")
        #expect(FileManager.default.fileExists(atPath: baselinePath.path))
        // Pre-calibration scoring keeps every M4–M7 family at default
        // .possible per PRD §3.5 corollary, so the persisted entries
        // list is empty for the fixture above — that's the correct
        // symmetric snapshot of today's drift surface.
        let loaded = InteractionBaselineLoader.load(startingFrom: directory)
        #expect(loaded.baseline.entries.isEmpty)
    }

    // MARK: - Helpers

    private func makeSuggestion(
        tier: Tier,
        predicate: String,
        family: InteractionInvariantFamily = .conservation
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: family,
            reducerQualifiedName: "Inbox.body",
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: family,
            reducerQualifiedName: "Inbox.body",
            reducerLocation: "Sources/MyApp/Inbox.swift:1",
            stateTypeName: "Inbox.State",
            actionTypeName: "Inbox.Action",
            predicate: predicate,
            score: tier == .strong ? 80 : (tier == .verified ? 90 : 30),
            tier: tier,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: firstSeenAt
        )
    }

    private func makeFixtureDirectoryWithPackageManifest(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscoverInteractionUpdateBaselineTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("// stub manifest for tests".utf8)
            .write(to: base.appendingPathComponent("Package.swift"))
        let sources = base.appendingPathComponent("Sources/MyApp")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        return base
    }

    private func writeFile(
        in directory: URL,
        relativePath: String,
        named name: String,
        contents: String
    ) throws {
        let dir = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: dir.appendingPathComponent(name))
    }
}

/// V1.89 — appending DiscoverOutput sink. Unlike `DPRecordingOutput`
/// (which overwrites on each write), this preserves the full call
/// sequence so tests can assert against both the baseline-write
/// status line AND the renderer output when --update-baseline is set.
private final class UpdateBaselineRecordingOutput: DiscoverOutput, @unchecked Sendable {
    var lines: [String] = []
    func write(_ text: String) {
        lines.append(text)
    }
}
