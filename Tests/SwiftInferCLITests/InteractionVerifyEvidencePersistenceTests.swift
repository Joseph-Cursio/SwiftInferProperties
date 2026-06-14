import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// Cycle 111 — durable proof of the interaction verify-evidence
/// *producer*. `VerifyInteractionPipeline.runWithInvariant` now upserts
/// each measured outcome into the shared `.swiftinfer/verify-evidence.json`
/// store, keyed by the invariant's identity — the join key the
/// (cycle 112) `discover-interaction` consumer will look up via
/// `suggestion.identity.normalized`.
///
/// These tests drive the recording leg in isolation (no subprocess
/// build): the end-to-end "measured-bothPass from a plain process" proof
/// already lives in `InteractionVerifyMeasuredExecutionTests`. What's new
/// in cycle 111 — and proven here — is that the parsed outcome reaches
/// disk under the right key, in the right shape, for every category.
@Suite("Interaction verify-evidence persistence (cycle 111 producer)")
struct InteractionVerifyEvidenceTests {

    @Test("a measured-bothPass outcome is persisted under the invariant's normalized identity")
    func bothPassPersistsUnderTheInvariantIdentity() throws {
        let directory = try makeFixtureDirectory(name: "InteractionBothPass")
        defer { try? FileManager.default.removeItem(at: directory) }

        let invariant = makeInvariant(predicate: ".refresh")
        let result = InteractionVerifyOutcomeParser.Result(
            outcome: .measuredBothPass,
            totalRuns: 1_024,
            cleanRuns: 1_024,
            detail: "totalRuns=1024 clean=1024"
        )

        VerifyInteractionPipeline.recordEvidence(
            invariant: invariant,
            result: result,
            workingDirectory: directory
        )

        let reloaded = VerifyEvidenceStore.load(startingFrom: directory)
        #expect(reloaded.log.records.count == 1)

        // The crux of the whole join: the persisted key is *exactly* what
        // the discover-side consumer looks up. If these ever drift, the
        // evidence is written but never found.
        let stored = try #require(reloaded.log.record(for: invariant.identity.normalized))
        #expect(stored.outcome == .measuredBothPass)
        #expect(stored.template == "idempotence")
        #expect(stored.detail == "totalRuns=1024 clean=1024")
    }

    @Test("a measured-defaultFails outcome is also persisted (so the consumer can suppress)")
    func defaultFailsAlsoPersists() throws {
        let directory = try makeFixtureDirectory(name: "InteractionDefaultFails")
        defer { try? FileManager.default.removeItem(at: directory) }

        let invariant = makeInvariant(predicate: ".increment")
        let result = InteractionVerifyOutcomeParser.Result(
            outcome: .measuredDefaultFails,
            detail: "at sequence index 3",
            failingSequenceIndex: 3
        )

        VerifyInteractionPipeline.recordEvidence(
            invariant: invariant,
            result: result,
            workingDirectory: directory
        )

        let stored = try #require(
            VerifyEvidenceStore.load(startingFrom: directory)
                .log.record(for: invariant.identity.normalized)
        )
        #expect(stored.outcome == .measuredDefaultFails)
        #expect(stored.detail == "at sequence index 3")
    }

    @Test("a re-run upserts: the latest outcome replaces the prior one for the same identity")
    func reRunUpsertsLatestOutcome() throws {
        let directory = try makeFixtureDirectory(name: "InteractionUpsert")
        defer { try? FileManager.default.removeItem(at: directory) }

        let invariant = makeInvariant(predicate: ".refresh")

        // First run: build/run couldn't measure yet.
        VerifyInteractionPipeline.recordEvidence(
            invariant: invariant,
            result: InteractionVerifyOutcomeParser.Result(
                outcome: .architecturalCoveragePending,
                detail: "kit pin not yet available"
            ),
            workingDirectory: directory
        )
        // Second run, same identity: now it measures clean.
        VerifyInteractionPipeline.recordEvidence(
            invariant: invariant,
            result: InteractionVerifyOutcomeParser.Result(
                outcome: .measuredBothPass,
                totalRuns: 1_024,
                cleanRuns: 1_024
            ),
            workingDirectory: directory
        )

        let reloaded = VerifyEvidenceStore.load(startingFrom: directory)
        #expect(reloaded.log.records.count == 1)
        #expect(reloaded.log.record(for: invariant.identity.normalized)?.outcome == .measuredBothPass)
    }

    // MARK: - Helpers

    /// Build an idempotence invariant whose identity is derived from the
    /// canonical `(family, reducer, predicate)` input — the exact
    /// derivation `InteractionTemplateFamily.makeSuggestion` uses on the
    /// discover side, so the persisted key matches by construction.
    private func makeInvariant(predicate: String) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .idempotence,
            reducerQualifiedName: "IDemo.reduce",
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .idempotence,
            reducerQualifiedName: "IDemo.reduce",
            reducerLocation: "Sources/IDemo/Reducer.swift:5",
            stateTypeName: "IDemo.State",
            actionTypeName: "IDemo.Action",
            predicate: predicate,
            score: 40,
            tier: .likely,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeFixtureDirectory(name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("interaction-verify-evidence")
            .appendingPathComponent(name)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // findPackageRoot walks up for Package.swift; an empty manifest is
        // enough to anchor the package root here.
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
        return directory
    }
}
