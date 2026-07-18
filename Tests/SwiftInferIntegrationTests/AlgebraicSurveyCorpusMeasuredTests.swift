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

    @Test("curated corpus verifies six measured families (12 bothPass + 5 defaultFails)")
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
        // 14 → 17 (+3 bothPass): the catalogue-work templates (2026-07) surface
        // three more true positives on this corpus — `involution` on
        // `Toggle.reversed` and `Latch.reversed` (`f(f(x)) == x`), and
        // `binary-idempotence` on `Confidence.meet` (`meet(x, x) == x`). (Latch's
        // `reversed` is a buggy *reverse* that returns self unchanged, but the
        // identity IS an involution, so it bothPasses the involution law — the
        // reverse-bug is the dual-style `defaultFails`, a different law.)
        // 17 → 15 (B24): the associativity/commutativity templates no longer fire
        // on a bare `(T,T)->T` shape without corroboration. `join` / `meet` are
        // in the semilattice-verb corroboration set, so their four true positives
        // (assoc + comm, both bothPass) survive — but `leftBiased`, an arbitrary
        // projection with no algebraic name, is now declined at PROPOSAL rather
        // than caught at verify, dropping its associativity true positive and its
        // commutativity false positive (the corpus's only commutativity
        // defaultFails). Net −2 records: one bothPass, one defaultFails.
        // 15 → 17 (B32): idempotence now accepts the instance self-form
        // (`self -> Self`), so it proposes on the two `reversed()` instance
        // methods — exactly as it already does on involution-named FREE functions.
        // Both are correct measured outcomes: `Latch.reversed` is the buggy
        // identity (`f(x) == x`), so idempotence `f(f(x)) == f(x)` holds →
        // bothPass; `Toggle.reversed` is a genuine involution, so idempotence is
        // false → defaultFails (the involution law, surfaced separately, is the
        // right one). Net +2: one bothPass, one defaultFails.
        #expect(records.count == 17)
        #expect(records.filter { $0.outcome == .measuredBothPass }.count == 12)
        #expect(records.filter { $0.outcome == .measuredDefaultFails }.count == 5)
        // The catalogue-work true positives.
        #expect(hasRecord(records, "involution", .measuredBothPass))
        #expect(hasRecord(records, "binary-idempotence", .measuredBothPass))
        // `join` / `meet` semilattice ops — associativity/commutativity true
        // positives (corroborated by the semilattice-verb set post-B24), plus the
        // idempotence true positive.
        #expect(hasRecord(records, "commutativity", .measuredBothPass))
        #expect(hasRecord(records, "associativity", .measuredBothPass))
        #expect(hasRecord(records, "idempotence", .measuredBothPass))
        // The first verifying round-trip in the project — the `Move.encode`/
        // `Move.decode` bijection bothPasses, alongside the spurious
        // `atLeastMedium`/`bumpUp` endomorphism pairing that defaultFails.
        #expect(hasRecord(records, "round-trip", .measuredBothPass))
        #expect(hasRecord(records, "round-trip", .measuredDefaultFails))
        // monotonicity: `score` (strictly increasing) bothPasses; `priority`
        // (curated name, non-monotone) is disproven by execution.
        #expect(hasRecord(records, "monotonicity", .measuredBothPass))
        #expect(hasRecord(records, "monotonicity", .measuredDefaultFails))
        // dual-style-consistency on a CUSTOM carrier: `Toggle` (mutating +
        // non-mutating twins agree) bothPasses; `Latch` (buggy non-mutating
        // twin) is disproven by execution.
        #expect(hasRecord(records, "dual-style-consistency", .measuredBothPass))
        #expect(hasRecord(records, "dual-style-consistency", .measuredDefaultFails))
    }

    private func hasRecord(
        _ records: [VerifyEvidence],
        _ template: String,
        _ outcome: VerifyEvidenceOutcome
    ) -> Bool {
        records.contains { $0.template == template && $0.outcome == outcome }
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
