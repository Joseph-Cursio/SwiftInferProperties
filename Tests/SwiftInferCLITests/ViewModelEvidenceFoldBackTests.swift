import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The fold-back the ViewModel survey shipped without: verify → persist →
/// `discover-interaction` re-tiers. Recorded as §8.1 of
/// `docs/design/observable-carrier-m1prime-verify-milestone.md` — the milestone
/// ticked this item on a commit that added a recorder, two test suites and **no
/// production call site**, so the loop stayed open for two months while a green
/// measured suite named for the join reported success.
///
/// **The arm that matters is `runLiveRecordsWhatItVerified`.** The pre-existing
/// suite proved the recorder worked by calling it directly, which is exactly why
/// it could not notice that nothing else did. These tests drive the survey
/// entry point instead, with an injected runner so no `swift build` is spawned.
@Suite("ViewModel evidence fold-back — the loop discover-interaction reads")
struct ViewModelEvidenceFoldBackTests {

    // MARK: - Fixtures

    /// A model with two mutually-exclusive presentation Optionals (so
    /// `ViewModelCardinalityResolver` resolves) and a collection + count pair
    /// (so `ViewModelConservationResolver` does too).
    private static let modelSource = """
    import Observation

    @Observable
    final class RouterModel {
        var presentedSheet: String?
        var presentedAlert: String?
        var items: [String] = []
        var itemCount: Int = 0

        func dismissAll() {
            presentedSheet = nil
            presentedAlert = nil
        }
    }
    """

    private static func makeCorpus() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-foldback-corpus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try modelSource.write(
            to: directory.appendingPathComponent("RouterModel.swift"),
            atomically: true,
            encoding: .utf8
        )
        return directory
    }

    /// The evidence store anchors on the nearest `Package.swift`, so a bare
    /// temp directory would send records somewhere else entirely.
    private static func makePackageRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-foldback-pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "// swift-tools-version: 6.1\nimport PackageDescription\nlet package = Package(name: \"P\")"
            .write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        return root
    }

    private static func candidates() throws -> [ViewModelCandidate] {
        let corpus = try makeCorpus()
        defer { try? FileManager.default.removeItem(at: corpus) }
        return try ViewModelDiscoverer.discover(directory: corpus)
    }

    private static func entry(
        _ typeName: String,
        _ family: String,
        _ result: ViewModelVerifyInteractionPipeline.StepResult
    ) -> ViewModelVerifyInteractionSurvey.Entry {
        .init(typeName: typeName, family: family, result: result)
    }

    private static let passed = ViewModelVerifyInteractionPipeline.StepResult.ran(
        .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0)
    )

    // MARK: - The wiring itself

    @Test("runLive persists what it verified, so the loop is closed end to end")
    func runLiveRecordsWhatItVerified() throws {
        let corpus = try Self.makeCorpus()
        defer { try? FileManager.default.removeItem(at: corpus) }
        let packageRoot = try Self.makePackageRoot()
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        let render = try ViewModelVerifyInteractionSurvey.runLive(
            sourceDirectory: corpus,
            userModuleName: "Fixture",
            packageRoot: packageRoot,
            workdirRoot: packageRoot
        ) { _, _, _ in
            .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0)
        }

        let records = VerifyEvidenceStore.load(startingFrom: packageRoot).log.records
        #expect(!records.isEmpty, "runLive verified invariants and persisted none — the loop is open again")
        #expect(records.allSatisfy { $0.outcome == .measuredBothPass })
        #expect(render.contains("evidence: recorded"))
    }

    /// The control. If the runner reports a refutation, that must reach the
    /// store too — an evidence channel that only ever records passes would
    /// promote laws and never suppress them.
    @Test("a refutation is persisted as well as a pass")
    func runLiveRecordsRefutations() throws {
        let corpus = try Self.makeCorpus()
        defer { try? FileManager.default.removeItem(at: corpus) }
        let packageRoot = try Self.makePackageRoot()
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        _ = try ViewModelVerifyInteractionSurvey.runLive(
            sourceDirectory: corpus,
            userModuleName: "Fixture",
            packageRoot: packageRoot,
            workdirRoot: packageRoot
        ) { _, _, _ in
            .defaultFails(
                .init(
                    trial: 3,
                    input: "[.dismissAll, .dismissAll]",
                    forwardResult: "presentedSheet != nil",
                    inverseResult: "presentedAlert != nil",
                    shrink: nil
                )
            )
        }

        let records = VerifyEvidenceStore.load(startingFrom: packageRoot).log.records
        #expect(!records.isEmpty)
        #expect(records.allSatisfy { $0.outcome == .measuredDefaultFails })
    }

    /// What the whole thing is FOR: the persisted record must carry the
    /// identity `discover-interaction` computes, or it joins nothing. Keying is
    /// the part most likely to rot, since identity is
    /// `family::typeName::subjects` and the survey verifies a different string.
    @Test("the persisted identity is the one the discover side computes")
    func persistedIdentityMatchesTheDiscoverSide() throws {
        let corpus = try Self.makeCorpus()
        defer { try? FileManager.default.removeItem(at: corpus) }
        let packageRoot = try Self.makePackageRoot()
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        _ = try ViewModelVerifyInteractionSurvey.runLive(
            sourceDirectory: corpus,
            userModuleName: "Fixture",
            packageRoot: packageRoot,
            workdirRoot: packageRoot
        ) { _, _, _ in
            .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0)
        }

        let recorded = Set(VerifyEvidenceStore.load(startingFrom: packageRoot).log.records.map(\.identityHash))
        let discoverSide = Set(
            try Self.candidates()
                .flatMap {
                    ViewModelInteractionAnalyzer.suggestions(
                        for: $0,
                        firstSeenAt: Date(timeIntervalSince1970: 0)
                    )
                }
                .map(\.identity.normalized)
        )
        #expect(!recorded.isEmpty)
        #expect(
            recorded.isSubset(of: discoverSide),
            "a recorded identity that discover never computes joins nothing: \(recorded.subtracting(discoverSide))"
        )
    }

    // MARK: - The pairing rule

    @Test("a verdict is paired with the one suggestion it measured")
    func pairsAnUnambiguousVerdict() throws {
        let candidates = try Self.candidates()
        let model = try #require(candidates.first)
        let folded = ViewModelVerifyInteractionSurvey.foldBack(
            candidates: candidates,
            entries: [Self.entry(model.typeName, "cardinality", Self.passed)],
            firstSeenAt: Date(timeIntervalSince1970: 0)
        )
        #expect(folded.paired.count == 1)
        #expect(folded.paired.first?.suggestion.family == .cardinality)
        #expect(folded.unpairable.isEmpty)
    }

    /// The soundness arm. An unknown carrier has no suggestion to key against,
    /// and recording anyway would attach a measured verdict to whatever the
    /// store's nearest neighbour happened to be.
    @Test("a verdict with no matching suggestion is withheld, not guessed")
    func withholdsWhenNothingMatches() throws {
        let candidates = try Self.candidates()
        let folded = ViewModelVerifyInteractionSurvey.foldBack(
            candidates: candidates,
            entries: [Self.entry("NoSuchModel", "cardinality", Self.passed)],
            firstSeenAt: Date(timeIntervalSince1970: 0)
        )
        #expect(folded.paired.isEmpty)
        #expect(folded.unpairable.map(\.matches) == [0])
    }

    @Test("a skipped entry contributes no evidence")
    func skippedEntriesAreNotEvidence() throws {
        let candidates = try Self.candidates()
        let model = try #require(candidates.first)
        let folded = ViewModelVerifyInteractionSurvey.foldBack(
            candidates: candidates,
            entries: [Self.entry(model.typeName, "cardinality", .skipped(reason: "requires arguments"))],
            firstSeenAt: Date(timeIntervalSince1970: 0)
        )
        #expect(folded.paired.isEmpty)
        #expect(folded.unpairable.isEmpty, "a skip is an absence of measurement, not an unpairable one")
    }

    @Test("a withheld verdict is disclosed in the render, never dropped silently")
    func disclosesWithheldVerdicts() {
        let folded = ViewModelVerifyInteractionSurvey.FoldBack(
            paired: [],
            unpairable: [.init(typeName: "RouterModel", family: "referential-integrity", matches: 3)]
        )
        let render = ViewModelVerifyInteractionSurvey.render(
            target: "Fixture",
            entries: [Self.entry("RouterModel", "referential-integrity", Self.passed)],
            folded: folded
        )
        #expect(render.contains("NOT recorded"))
        #expect(render.contains("3 suggestions"))
    }
}
