import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Real-world discovery regression guard over a corpus of **unmodified**
/// Point-Free TCA reducer sources (`Tests/Fixtures/tca-examples-corpus/`,
/// vendored from swift-composable-architecture at commit `2fc6ed2`; see that
/// directory's `ATTRIBUTION.md`).
///
/// These are pure-parse discovery calls — `ReducerDiscoverer` +
/// `InteractionTemplateEngine`, no compilation — so this is fast and hermetic.
/// It validates that the surface works on authentic reducers, not just
/// synthetic fixtures, and it pins the headline fact that motivated the TCA
/// determinism work: **every real-world reducer is `carrier:tca`.**
///
/// Counts are exact against the frozen corpus (a genuine regression guard); if
/// discovery legitimately improves, update the baseline here.
@Suite("TCA examples corpus — real-world discovery coverage")
struct TCAExamplesCorpusDiscoveryTests {

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferTemplatesTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("tca-examples-corpus")
    }()

    @Test("discovers 19 real Point-Free reducers, every one carrier:tca")
    func discoversRealReducersAllTCA() throws {
        let candidates = try ReducerDiscoverer.discover(directory: Self.fixtureDirectory)
        #expect(candidates.count == 19)
        #expect(candidates.allSatisfy { $0.carrierKind == .tca })
        // A spread of authentic reducers is present.
        let names = Set(candidates.map(\.qualifiedName))
        #expect(names.contains("Counter.body"))
        #expect(names.contains("Todos.body"))
        #expect(names.contains("Search.body"))
        #expect(names.contains("Nested.body"))
    }

    @Test("witness families fire on real reducers; determinism is (still) absent")
    func witnessFamiliesFireDeterminismAbsent() throws {
        let candidates = try ReducerDiscoverer.discover(directory: Self.fixtureDirectory)
        let suggestions = try InteractionTemplateEngine.analyze(
            candidates: candidates,
            sourcesDirectory: Self.fixtureDirectory,
            firstSeenAt: ISO8601DateFormatter().date(from: "2026-07-03T00:00:00Z")!
        )
        var byFamily: [InteractionInvariantFamily: Int] = [:]
        for suggestion in suggestions { byFamily[suggestion.family, default: 0] += 1 }
        // The witness-based families reach real TCA code.
        #expect(byFamily[.idempotence] == 3)
        #expect(byFamily[.biconditional] == 1)
        #expect(byFamily[.cardinality] == 1)
        // Determinism does NOT surface — it's gated to the .redux family, and
        // every real reducer here is .tca. This is the gap the TCA determinism
        // work (docs/tca-determinism-verify-scope.md) closes; when it lands,
        // this expectation flips to a positive count.
        #expect(byFamily[.determinism, default: 0] == 0)
    }
}
