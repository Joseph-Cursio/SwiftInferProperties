import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Item 2 slice 3 — `IdentifiedActionOf<Child>` composition payloads, measured.
/// The `tca-identified-action-corpus` pairs a `.forEach` parent (`RowList`,
/// `case rows(IdentifiedActionOf<Row>)`) with a `UUID`-id child (`Row`). The
/// verifier explores `Action.rows(.element(id: <canned UUID>, action: .increment))`
/// — a canonical identified-array element, no `Gen` over the child needed. Both
/// reducers are deterministic, so the determinism family verifies `bothPass`,
/// proving the emitted `.element(id:action:)` compiles against CA and drives a
/// deterministic (no-op-against-empty-rows) transition.
///
/// Real `swift build` against ComposableArchitecture — tagged `.subprocess`.
///
/// ⚠️ TOOLCHAIN NOTE. Runs under **Swift 6.3.3** only (Swift 6.2.4 has a
/// `swift-frontend` bug that crashes before the stub is reached — upstream of
/// this feature). Run under 6.3.3+ (e.g. `swiftly use 6.3.3`). See
/// `docs/tca-determinism-followups.md`.
@Suite("TCA identified-action corpus — IdentifiedActionOf payload measured", .tags(.subprocess))
struct IdentifiedActionCorpusMeasuredTests {

    @Test("a .forEach parent with an IdentifiedActionOf<Child> action verifies (bothPass)")
    func identifiedActionPayloadVerifies() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tca-identified-action-corpus-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "TCAIdentifiedActionCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "TCAIdentifiedActionCorpus",
            familyFilter: "determinism",
            sequenceCount: 64,
            workingDirectory: root
        )
        // Parent (RowList) + child (Row) each surface one determinism identity.
        #expect(summary.contains("Identities: 2 (--family determinism)"))
        #expect(summary.contains("2 measured-bothPass"))

        let evidence = VerifyEvidenceStore.load(startingFrom: root).log.records
        #expect(evidence.count == 2)
        #expect(evidence.allSatisfy { $0.outcome == .measuredBothPass })

        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "TCAIdentifiedActionCorpus",
            includePossible: true,
            workingDirectory: root
        )
        let parentBlock = discovered
            .components(separatedBy: "[Interaction-Invariant Suggestion]")
            .first { $0.contains("Family:    determinism") && $0.contains("RowList") }
        #expect(parentBlock?.contains("(Verified)") == true)
        // Slice-3 payoff: `rows` is explored (full coverage), so the parent
        // carries no partial-exploration `excluded: rows` disclosure.
        #expect(parentBlock?.contains("excluded: rows") != true)
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("tca-identified-action-corpus")
    }()
}
