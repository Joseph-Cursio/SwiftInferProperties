import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Item-2 slice 2 — `Result<_, any Error>` composition payloads, measured. The
/// `tca-composition-payload-corpus`'s `NumberFact` reducer carries a
/// `case response(Result<String, any Error>)`; the verifier explores
/// `Action.response(.failure(CancellationError()))` — a canned type-erased error,
/// no `Gen<String>` needed. A `measured-bothPass` proves the emitted
/// `.failure(CancellationError())` compiles against CA and drives the reducer's
/// failure branch deterministically.
///
/// Real `swift build` against ComposableArchitecture — tagged `.subprocess`,
/// 6.3.3-gated (see `docs/tca-determinism-followups.md`).
@Suite("TCA composition-payload corpus — Result payload measured", .tags(.subprocess))
struct CompositionPayloadCorpusMeasuredTests {

    @Test("a reducer with a Result<_, any Error> action verifies determinism (bothPass)")
    func resultPayloadVerifies() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tca-composition-payload-corpus-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "TCACompositionCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "TCACompositionCorpus",
            familyFilter: "determinism",
            sequenceCount: 64,
            workingDirectory: root
        )
        #expect(summary.contains("Identities: 1 (--family determinism)"))
        #expect(summary.contains("1 measured-bothPass"))

        let evidence = VerifyEvidenceStore.load(startingFrom: root).log.records
        #expect(evidence.count == 1)
        #expect(evidence.allSatisfy { $0.outcome == .measuredBothPass })

        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "TCACompositionCorpus",
            includePossible: true,
            workingDirectory: root
        )
        let block = discovered
            .components(separatedBy: "[Interaction-Invariant Suggestion]")
            .first { $0.contains("Family:    determinism") && $0.contains("NumberFact") }
        #expect(block?.contains("(Verified)") == true)
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("tca-composition-payload-corpus")
    }()
}
