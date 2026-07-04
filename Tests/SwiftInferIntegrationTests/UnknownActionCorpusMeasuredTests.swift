import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Measured baseline for the `unknownActionIsNoOp` family — the open-alphabet
/// redux guarantee `reduce(s, unknown) == s`. The verifier mints a fresh probe
/// type conforming to the reducer's open `Action` protocol (a type the reducer
/// cannot recognise), applies it, and asserts State is unchanged.
///
/// The two-reducer corpus (`Tests/Fixtures/unknown-action-corpus/`) proves the
/// check has teeth:
///   - `NoOpCounter` — default branch leaves State untouched → bothPass →
///     Verified;
///   - `LeakyReducer` — default branch mutates State (bumps `unknownHits`) →
///     `reduce(s, unknown) != s` → the stub precondition traps → defaultFails →
///     suppressed.
///
/// Plain-Swift protocol dispatch, no ComposableArchitecture — a real
/// `swift build` but with no CA dependency, so it runs under any modern
/// toolchain and is fast. Tagged `.subprocess`.
@Suite("Unknown-action-is-no-op corpus — open-alphabet redux measured baseline", .tags(.subprocess))
struct UnknownActionCorpusMeasuredTests {

    @Test("no-op default passes; a State-mutating default fails — 1 bothPass + 1 defaultFails")
    func unknownActionNoOpSplits() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("unknown-action-corpus-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "UnknownActionCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "UnknownActionCorpus",
            familyFilter: "unknown-action-is-no-op",
            sequenceCount: 64,
            workingDirectory: root
        )
        #expect(summary.contains("Identities: 2 (--family unknown-action-is-no-op)"))
        #expect(summary.contains("1 measured-bothPass"))
        #expect(summary.contains("1 measured-defaultFails"))

        let evidence = VerifyEvidenceStore.load(startingFrom: root).log.records
        #expect(evidence.count == 2)
        #expect(evidence.filter { $0.outcome == .measuredBothPass }.count == 1)
        #expect(evidence.filter { $0.outcome == .measuredDefaultFails }.count == 1)

        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "UnknownActionCorpus",
            includePossible: true,
            workingDirectory: root
        )
        let blocks = discovered.components(separatedBy: "[Interaction-Invariant Suggestion]")
        func noOpBlock(reducer: String) -> String? {
            blocks.first {
                $0.contains("Family:    unknown-action-is-no-op") && $0.contains(reducer)
            }
        }
        // The genuine no-op promotes to Verified; the leaky reducer is suppressed.
        #expect(noOpBlock(reducer: "NoOpCounter")?.contains("(Verified)") == true)
        #expect(noOpBlock(reducer: "LeakyReducer") == nil)
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("unknown-action-corpus")
    }()
}
