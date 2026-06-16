import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

// V1.51.D — Layer-2(a) blind-spot guard. Asserts the indexer→verify
// path resolves cleanly for at least one cycle-27 entry, so a future
// cycle reintroducing the carrier-name asymmetry (V1.50.B routing
// fix, V1.51.A canonicalization) fails immediately instead of after
// another full-surface survey.
//
// **Why a unit test rather than a subprocess integration test.** The
// load-bearing guard here is the resolution pipeline — `buildStubBundle`
// must produce a valid stub bundle for an entry the indexer actually
// emits. The subprocess `swift build` step is already exercised by
// V1.42.D / V1.44.E / V1.45.E / V1.46.D / V1.47.G / V1.48.H / V1.49.F
// (all on synthetic SemanticIndexEntry inputs). v1.51.D's bridge is
// "synthetic vs real-indexer": load a real-indexer-produced entry from
// the committed fixture, run buildStubBundle, assert no
// VerifyError-class exception fires. If the bridge breaks (e.g., the
// canonicalization table loses the "Complex" entry, or a future
// cycle's emitter rejects a carrier the indexer produces), this test
// fails at unit-test speed.

@Suite("V1.51.D — end-to-end indexer→verify resolution guard")
struct V151EndToEndFromIndexTests {

    /// The cycle-27 fixture's merged index path. Committed to the
    /// repo by V1.50.A; rebuildable via
    /// `fixtures/cycle27-surface/build-index.sh`.
    private static let fixtureIndexPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Tests/SwiftInferCLITests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("fixtures/cycle27-surface/.swiftinfer/index.json")

    /// Cycle-27 #3 pick: Complex.exp(_:) × log(_:) round-trip.
    /// Per `docs/calibration-cycle-27-data/triage-decisions.json`.
    private static let expLogIdentityHash = "0x4949D576A215E8C1"

    @Test("real-indexer Complex.exp×log entry resolves via buildStubBundle (no architectural error)")
    func expLogEntryResolvesEndToEnd() throws {
        // V1.51.D weak assertion: the entry must produce a stub bundle
        // without throwing a VerifyError — i.e., the carrier-name
        // canonicalization (V1.51.A) + routing + curated pair lookup
        // all succeed. The downstream `swift build` step is the
        // subject of v1.52+'s gap-closing (operator-named functions
        // like `/(z:w:)` and free-function name resolution).
        let entry = try Self.loadEntry(identityHash: Self.expLogIdentityHash)
        // Sanity: the real-indexer entry has carrier "Complex" (bare).
        // If a future indexer change produces "Complex<Double>" or
        // similar, the test's premise shifts but the guard still
        // holds — the assertion is on buildStubBundle's success.
        #expect(entry.typeName == "Complex")
        #expect(entry.primaryFunctionName == "exp(_:)")
        // Load-bearing: no throws.
        let bundle = try SwiftInferCommand.Verify.buildStubBundle(
            entry: entry,
            budget: .small
        )
        // Sanity: the bundle came from the v1.46 hardcoded round-trip
        // path (Complex<Double> after canonicalization). Its source
        // should include the canonical Complex generator.
        #expect(bundle.source.contains("Complex"))
        #expect(bundle.rendererContext.templateName == "round-trip")
    }

    @Test("real-indexer index loads with the expected cycle-27 surface count (82, post-cycle-148 Lever A)")
    func cycle27FixtureHasExpectedSurfaceCount() throws {
        let data = try Data(contentsOf: Self.fixtureIndexPath)
        let store = try JSONDecoder().decode(IndexStore.Index.self, from: data)
        // V1.57.A's private/fileprivate filter dropped the v1.29-era 109
        // baseline to 103 (cycle 54). Cycle 148 (Lever A) extended the
        // filter to explicit-`internal` + `_`-prefixed-enclosing-type
        // declarations, dropping 21 non-public/SPI false positives → 82.
        // See docs/calibration-cycle-148-findings.md.
        #expect(store.entries.count == 82)
    }

    // **Why no dual-style E2E test in v1.51**. The cycle-27 fixture's
    // dual-style entries all reference OC's generic associated types
    // (`OrderedSet.UnorderedView`, `OrderedDictionary.Elements`, etc.)
    // which fail at carrier resolution before V1.51.B's curated-pair
    // expansion is consulted. V1.51.B's expansion is exercised by
    // V151DualStyleExpansionTests's unit tests; full real-indexer
    // dual-style E2E coverage waits for v1.52+'s generic-carrier
    // TypeShape work.

    // MARK: - Helpers

    private static func loadEntry(identityHash: String) throws -> SemanticIndexEntry {
        let data = try Data(contentsOf: fixtureIndexPath)
        let store = try JSONDecoder().decode(IndexStore.Index.self, from: data)
        guard let entry = store.entries.first(where: { $0.identityHash == identityHash }) else {
            throw NSError(
                domain: "V151EndToEndFromIndexTests",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "fixture index doesn't contain entry with identityHash \(identityHash); "
                        + "regenerate via fixtures/cycle27-surface/build-index.sh"
                ]
            )
        }
        return entry
    }
}
