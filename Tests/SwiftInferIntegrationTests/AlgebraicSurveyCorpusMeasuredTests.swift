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
        // 17 → 19: a later catalogue-template widening added +2 measured records
        // (one bothPass, one defaultFails) — all legitimate algebraic picks — but
        // this slow, fast-suite-skipped measured baseline was not refreshed at the
        // time. Confirmed by re-running the survey (13 bothPass + 6 defaultFails).
        // NB the commutativity set-verb fix (intersection / symmetricDifference)
        // is corpus-orthogonal — this corpus has no such functions — verified by
        // identical survey discovery with and without it.
        // 19 → 18, and defaultFails 6 → 5. The dropped record is the one the comment below
        // calls "the spurious `atLeastMedium`/`bumpUp` endomorphism pairing", and
        // `ConfidenceUnary.swift` diagnoses it precisely: "the round-trip template pairs
        // same-signature unary functions COMBINATORIALLY as forward/inverse candidates …
        // there's no true inverse pair here."
        //
        // `endomorphismRoundTripPair` now suppresses it at DISCOVERY, so verify never sees
        // it. This baseline was pinning the symptom of a known defect — propose a false law,
        // build a workdir, run 100 trials, record `measuredDefaultFails` — and a refuted
        // false positive is still a false positive that cost a verify cycle.
        //
        // bothPass stays 13, which is the part worth noticing: `Move.encode`/`Move.decode` is
        // a curated inverse-name pair and survived untouched. That is the counter-signal's
        // name exemption confirmed on a MEASURED corpus rather than on a fixture.
        //
        // 18 → 20 (2026-08-21): `role-postcondition` ships and fires on `Toggle.reversed`
        // and `Latch.reversed`. **Both rows are `unsupported-template` — they do NOT
        // execute**, because the template is discovery-only, like 21 of the catalogue's 36
        // names. So the total moves and the two measured counts below do not, which is the
        // shape worth checking rather than the total: a new template that added *executing*
        // rows would move `bothPass` or `defaultFails` too.
        //
        // Worth recording against the comment above, which notes that `Latch.reversed` is a
        // buggy reverse returning `self` unchanged: **the role law would not catch it
        // either.** `reversed` owes only "the result has the same element count as the
        // input", and a self-returning reverse satisfies that. It is one of the two roles
        // marked `isStrong == false` for exactly this reason, and it is a live example of
        // why that flag exists rather than a hypothetical one.
        #expect(records.count == 20)
        #expect(records.filter { $0.outcome == .measuredBothPass }.count == 13)
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
        // The first verifying round-trip in the project — the `Move.encode`/`Move.decode`
        // bijection bothPasses.
        #expect(hasRecord(records, "round-trip", .measuredBothPass))
        // And the spurious `atLeastMedium`/`bumpUp` endomorphism pairing is now ABSENT rather
        // than present-and-refuted. Asserted as an absence rather than deleted, so the
        // improvement is pinned: if the endomorphism counter regresses, this fails here
        // instead of quietly costing a verify cycle again.
        #expect(!hasRecord(records, "round-trip", .measuredDefaultFails))
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
