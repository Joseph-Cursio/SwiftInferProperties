import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// TestStore Trace Mining — the gold-standard measured proof (Slices 1–3
/// end-to-end). Packages `Tests/Fixtures/tca-trace-mining-corpus/` (a real
/// `@Reducer` with a payload-bearing `select(Int)` case), drops a sibling
/// `TestStore` test into the packaged root, and shows that the **payload-
/// generalized** mined ordering (`.select(0)` — the canned literal replacing
/// the test's `.select(5)`) is BOTH emitted into the verifier stub AND
/// compiles + runs through the real `.tca` verify path. Spawns a real
/// `swift build` resolving swift-composable-architecture; tagged `.subprocess`.
@Suite("TestStore Trace Mining — measured end-to-end proof", .tags(.subprocess))
struct TraceMiningMeasuredTests {

    @Test("a payload-generalized mined trace is emitted, compiles, and verifies bothPass")
    func generalizedTraceCompilesAndVerifies() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tca-trace-mining-corpus")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "TraceMiningCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        // The developer-authored TestStore test the miner reads. `.adjust(5)`
        // is payload-bearing; the selector generalizes it to the canned
        // `.adjust(0)` (Slice 3b). Only parsed by the extractor — never built.
        try writeTestStoreTest(into: root)

        // Proof 1 (no build): the emitted stub carries the *generalized*
        // ordering — `.adjust(0)` (not the test's `.adjust(5)`) + `.reset`,
        // seeded from a self-contained `TestStore(initialState:)` (Slice 3c).
        let seeded = try VerifyInteractionPipeline.resolveEmitAndSeed(
            target: "TraceMiningCorpus",
            pinRaw: "TraceFeature.body",
            workingDirectory: root
        )
        #expect(seeded.seedTraceCount == 1)
        #expect(seeded.stubSource.contains("(TraceFeature.State(), [.adjust(0), .reset]),"))

        // Proof 2 (build + run): the same mining feeds the survey's verifier,
        // so a `measured-bothPass` means the stub *containing* that generalized
        // ordering compiled and executed. A malformed `.adjust(0)` would fail
        // the build → architectural-coverage-pending, never bothPass. `reset`
        // is the sole surfaced identity (adjust is a non-witness name), so the
        // whole survey is one clean bothPass. `clean=1025` (1024 random + the
        // 1 mined ordering) is the direct fingerprint of replay-then-extend.
        let summary = try await VerifyInteractionSurvey.run(
            target: "TraceMiningCorpus",
            familyFilter: "idempotence",
            workingDirectory: root
        )
        #expect(summary.contains("[measured-bothPass]"))
        #expect(summary.contains("TraceFeature.body  idempotence  .reset"))
        #expect(summary.contains("replay-then-extend: checked 1 developer-authored trace"))
        #expect(summary.contains("clean=1025"))
        #expect(!summary.contains("architectural-coverage-pending"))
        #expect(!summary.contains("measured-defaultFails"))

        // The evidence records a bothPass (the survivor discover would promote).
        let stored = VerifyEvidenceStore.load(startingFrom: root)
        #expect(stored.log.records.contains { $0.outcome == .measuredBothPass })
        #expect(!stored.log.records.contains { $0.outcome == .measuredError })
    }

    private func writeTestStoreTest(into root: URL) throws {
        let dir = root.appendingPathComponent("Tests").appendingPathComponent("TraceMiningCorpusTests")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = """
        import ComposableArchitecture
        import XCTest

        final class TraceFeatureTests: XCTestCase {
            func testFlow() async {
                let store = TestStore(initialState: TraceFeature.State()) { TraceFeature() }
                await store.send(.adjust(5)) { $0.selected = 5 }
                await store.send(.reset) { $0.selected = 0 }
            }
        }
        """
        try Data(source.utf8).write(to: dir.appendingPathComponent("TraceFeatureTests.swift"))
    }

    /// `Tests/Fixtures/tca-trace-mining-corpus/`, resolved against `#filePath`.
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("tca-trace-mining-corpus")
    }()
}
