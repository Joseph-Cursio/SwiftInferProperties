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
/// `.subprocess`. Fourteen picks across six families → 9 bothPass + 5 defaultFails:
///   - commutativity/associativity: `join` / `meet` (semilattice ops) →
///     comm + assoc bothPass (4); `leftBiased` (a first-non-medium fold) →
///     assoc bothPass but comm defaultFails — execution distinguishes the two
///     properties on one function;
///   - idempotence: `atLeastMedium` (clamp-up) → bothPass; `bumpUp` (saturating
///     step) → defaultFails (the idempotence false positive);
///   - round-trip: `Move.encode`/`Move.decode` (a genuine bijection on the same
///     carrier) → bothPass, the FIRST verifying round-trip in the project; plus
///     one spurious endomorphism pairing (`atLeastMedium`/`bumpUp` — the
///     template over-generates same-signature unary functions) → defaultFails;
///   - monotonicity: `Confidence.score` (a strictly-increasing Int projection)
///     → bothPass; `Confidence.priority` (a curated-named but non-monotone
///     projection — `.medium` outranks `.high`) → defaultFails;
///   - dual-style-consistency: `Toggle.reverse`/`reversed` (mutating + non-mutating
///     twins that agree) → bothPass, the first dual-style verified on a CUSTOM
///     (non-OrderedCollections) carrier; `Latch.reverse`/`reversed` (the
///     non-mutating twin is buggy — returns self unchanged) → defaultFails.
@Suite("Algebraic survey corpus — measured baseline", .tags(.subprocess))
struct AlgebraicSurveyCorpusMeasuredTests {

    @Test("curated corpus verifies six measured families (9 bothPass + 5 defaultFails)")
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
        #expect(records.count == 14)
        #expect(records.filter { $0.outcome == .measuredBothPass }.count == 9)
        #expect(records.filter { $0.outcome == .measuredDefaultFails }.count == 5)
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
        // The first verifying round-trip in the project — the `Move.encode`/
        // `Move.decode` bijection bothPasses, alongside the spurious
        // `atLeastMedium`/`bumpUp` endomorphism pairing that defaultFails.
        #expect(records.contains {
            $0.template == "round-trip" && $0.outcome == .measuredBothPass
        })
        #expect(records.contains {
            $0.template == "round-trip" && $0.outcome == .measuredDefaultFails
        })
        // monotonicity: `score` (strictly increasing) bothPasses; `priority`
        // (curated name, non-monotone) is disproven by execution.
        #expect(records.contains {
            $0.template == "monotonicity" && $0.outcome == .measuredBothPass
        })
        #expect(records.contains {
            $0.template == "monotonicity" && $0.outcome == .measuredDefaultFails
        })
        // dual-style-consistency on a CUSTOM carrier: `Toggle` (mutating +
        // non-mutating twins agree) bothPasses; `Latch` (buggy non-mutating
        // twin) is disproven by execution.
        #expect(records.contains {
            $0.template == "dual-style-consistency" && $0.outcome == .measuredBothPass
        })
        #expect(records.contains {
            $0.template == "dual-style-consistency" && $0.outcome == .measuredDefaultFails
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
