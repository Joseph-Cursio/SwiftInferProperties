import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The first verify-ready CURATED ALGEBRAIC corpus. Packages
/// `Tests/Fixtures/algebraic-survey-corpus/` (the `Confidence` bounded-lattice
/// enum with static binary ops) and runs the measured `verify --all-from-index
/// --corpus-module` survey: the verifier path-depends on the packaged corpus +
/// `import`s its module, so the corpus's OWN types resolve as carriers (vs
/// cycle27-surface's library carriers). Demonstrates the algebraic
/// measured-verify path on a fresh public API surface — and the FIRST
/// verifying commutativity + associativity in the project (cycle27's were all
/// filtered false positives).
///
/// Spawns real `swift build`s resolving the algebraic deps; tagged
/// `.subprocess`. Nine picks across three families → 6 bothPass + 3 defaultFails:
///   - commutativity/associativity: `join` / `meet` (semilattice ops) →
///     comm + assoc bothPass (4); `leftBiased` (a first-non-medium fold) →
///     assoc bothPass but comm defaultFails — execution distinguishes the two
///     properties on one function;
///   - idempotence: `atLeastMedium` (clamp-up) → bothPass; `bumpUp` (saturating
///     step) → defaultFails (the idempotence false positive);
///   - round-trip: one spurious pairing (`atLeastMedium`/`bumpUp` — the template
///     over-generates same-signature unary functions) → defaultFails.
@Suite("Algebraic survey corpus — measured baseline", .tags(.subprocess))
struct AlgebraicSurveyCorpusMeasuredTests {

    @Test("curated Confidence corpus verifies commutativity/associativity/idempotence (6 bothPass + 3 defaultFails)")
    func measuredAlgebraicSplits() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("algebraic-survey-corpus")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "AlgebraicSurveyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        // Reindexes the corpus on demand, then surveys each pick by
        // path-depending on the corpus + importing its module.
        try await SwiftInferCommand.Verify.runAllFromIndex(
            indexPathOverride: nil,
            budgetString: "small",
            workingDirectory: root,
            maxParallel: 4,
            templateFilter: nil,
            corpusModuleName: "AlgebraicSurveyCorpus"
        )

        let records = VerifyEvidenceStore.load(startingFrom: root).log.records
        #expect(records.count == 9)
        #expect(records.filter { $0.outcome == .measuredBothPass }.count == 6)
        #expect(records.filter { $0.outcome == .measuredDefaultFails }.count == 3)
        // commutativity false positive (non-commutative `leftBiased`), its
        // associativity true positive, and the idempotence true positive.
        #expect(records.contains {
            $0.template == "commutativity" && $0.outcome == .measuredDefaultFails
        })
        #expect(records.contains {
            $0.template == "associativity" && $0.outcome == .measuredBothPass
        })
        #expect(records.contains {
            $0.template == "idempotence" && $0.outcome == .measuredBothPass
        })
    }

    /// `Tests/Fixtures/algebraic-survey-corpus/`, resolved against `#filePath`.
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("algebraic-survey-corpus")
    }()
}
