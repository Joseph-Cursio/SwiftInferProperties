import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 114 — end-to-end proof of `verify-interaction --all` over a
/// packaged corpus. Deliberately uses **two idempotence witnesses on the
/// same reducer** (`.refresh` + `.reset`) so the survey exercises the
/// serial-same-workdir path: both identities share the reducer-keyed verify
/// workdir, so they must run in series without clobbering — the exact
/// reason this survey is serial (not parallel) this cycle.
///
/// Spawns real `swift build` + verifier runs (two identities → two builds;
/// tens of seconds) — tagged `.subprocess`.
@Suite("verify-interaction --all — packaged-corpus measured survey", .tags(.subprocess))
struct VerifyInteractionSurveyMeasuredTests {

    /// One reducer, two curated-idempotent witnesses (`refresh`, `reset`,
    /// both collapse to `State(count: 0)`), a non-idempotent driver, `noop`.
    private static let counterSource = """
    public struct CounterReducer {
        public struct State: Equatable, Sendable {
            public var count: Int
            public init(count: Int = 0) { self.count = count }
        }
        public enum Action: CaseIterable, Sendable { case refresh, reset, increment, noop }
        public static func reduce(_ s: State, _ a: Action) -> State {
            switch a {
            case .refresh, .reset: return State(count: 0)
            case .increment: return State(count: s.count + 1)
            case .noop: return s
            }
        }
    }
    """

    @Test("--all --family idempotence surveys both witnesses serially and records bothPass for each")
    func surveyRecordsBothPassForEachIdentity() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-interaction-survey")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "IdempotenceCorpus",
            sourceFiles: [.init(name: "Counter.swift", contents: Self.counterSource)],
            into: parent
        )

        let rendered = try await VerifyInteractionSurvey.run(
            target: "IdempotenceCorpus",
            familyFilter: "idempotence",
            workingDirectory: root
        )

        // Both .refresh and .reset are idempotence identities on the one
        // reducer; both measure bothPass.
        #expect(rendered.contains("Identities: 2 (--family idempotence)"))
        #expect(rendered.contains("Summary: 2 measured-bothPass"))
        #expect(!rendered.contains("measured-defaultFails"))
        #expect(!rendered.contains("architectural-coverage-pending"))

        // Evidence persisted for both identities — the harvest the campaign
        // needs for discover-interaction to promote them.
        let stored = VerifyEvidenceStore.load(startingFrom: root)
        #expect(stored.log.records.count == 2)
        #expect(stored.log.records.allSatisfy { $0.outcome == .measuredBothPass })

        // Payoff: discover-interaction now reads that evidence and renders
        // both identities Verified (no extra build — discovery is AST-only).
        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "IdempotenceCorpus",
            workingDirectory: root
        )
        #expect(discovered.contains("(Verified)"))
        #expect(!discovered.contains("(Likely)"))
    }
}
