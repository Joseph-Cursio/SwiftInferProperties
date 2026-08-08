import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The census behind `docs/measurements/interaction-trap-attribution-census.md`:
/// of the refutations the interaction verifier reports, how many are the harness's
/// own invariant check firing, and how many are the subject trapping for its own
/// reasons?
///
/// **Why this is a census and not an assertion.** The per-corpus measured suites
/// already pin what each fixture *should* do. This asks a question across all of
/// them that none of them asks: whether `.measuredDefaultFails` is one population
/// or two. It therefore asserts almost nothing about the split — only that the
/// instrument works — and prints the tally for the doc.
///
/// **Opt-in.** It re-surveys six corpora that BATCH2 / BATCH4 / BATCH7 already
/// build, so leaving it on would add ~6 minutes to every `make test` to recompute
/// a number that only changes when the question is re-asked:
///
///     SWIFT_INFER_RUN_TRAP_CENSUS=1 swift test --filter TrapAttributionCensusMeasuredTests
///
/// It is still batched, because `SubprocessBatchCoverageTests` requires every
/// `*MeasuredTests` suite to be scheduled somewhere — and a suite that is skipped
/// by default but unbatched would silently become unrunnable if the gate were
/// removed. Disabled, it costs nothing there.
///
/// **The standing guard is elsewhere and cheap.** If a future family stops marking
/// its check, every genuine refutation silently reclassifies as an artifact —
/// caught by `InteractionTrapAttributionTests.everyFamilyMarksItsCheck`, which is
/// parameterised over `CaseIterable` and runs in the ~6s fast path. This census
/// answers a question; that test defends the answer.
@Suite(
    "Interaction trap attribution — census over the verify corpora",
    .tags(.subprocess),
    .enabled(
        if: ProcessInfo.processInfo.environment["SWIFT_INFER_RUN_TRAP_CENSUS"] != nil,
        "opt-in census; set SWIFT_INFER_RUN_TRAP_CENSUS=1"
    )
)
struct TrapAttributionCensusMeasuredTests {

    /// Corpora that contain at least one deliberate refutation, so the census has
    /// a non-empty numerator. `output-determinism` is excluded: a different
    /// emitter verifies it, and its traps are not action-sequence traps.
    struct Corpus: Sendable {
        let fixture: String
        let module: String
        let family: String?
    }

    static let corpora: [Corpus] = [
        Corpus(fixture: "cardinality-verify-corpus", module: "CardinalityVerifyCorpus", family: "cardinality"),
        Corpus(fixture: "conservation-survey-corpus", module: "ConservationSurveyCorpus", family: "conservation"),
        Corpus(fixture: "biconditional-verify-corpus", module: "BiconditionalVerifyCorpus", family: "biconditional"),
        Corpus(fixture: "refint-verify-corpus", module: "RefintVerifyCorpus", family: "referential-integrity"),
        Corpus(fixture: "determinism-verify-corpus", module: "DeterminismVerifyCorpus", family: "determinism"),
        Corpus(fixture: "idempotence-survey-corpus", module: "IdempotenceSurveyCorpus", family: "idempotence")
    ]

    @Test("census: attribute every measured refutation across the interaction corpora")
    func censusOverInteractionCorpora() async throws {
        var tally: [String: Int] = [:]
        var refutations = 0
        var lines: [String] = []

        for corpus in Self.corpora {
            let rendered = try await Self.survey(corpus)
            // The bracketed form is an entry; the survey also prints a per-corpus
            // tally line ("1 measured-defaultFails") that is a count, not a row.
            // Matching the bare name counted one phantom refutation per corpus.
            for line in rendered.components(separatedBy: "\n")
            where line.contains("[measured-defaultFails]") {
                refutations += 1
                let origin = Self.attribution(in: line)
                tally[origin, default: 0] += 1
                lines.append("  \(corpus.module.padding(toLength: 28, withPad: " ", startingAt: 0)) \(origin)")
            }
        }

        print("""

            ── interaction trap attribution census ──────────────────────────
            corpora surveyed : \(Self.corpora.count)
            refutations      : \(refutations)
            invariant check  : \(tally["invariantCheck", default: 0])
            subject code     : \(tally["subjectCode", default: 0])
            unattributable   : \(tally["unattributable", default: 0])
            unrecognised     : \(tally["?", default: 0])
            \(lines.joined(separator: "\n"))
            ─────────────────────────────────────────────────────────────────
            """)

        // The instrument, not the split. A census that attributed nothing would
        // report "no artifacts" and "the marker never reached stderr" identically
        // — the confident zero this repo keeps re-learning.
        #expect(refutations > 0, "no refutations surveyed — the census has no numerator")
        #expect(
            tally["?", default: 0] == 0,
            "a refutation carried no recognisable attribution — the detail format moved"
        )
    }

    private static func attribution(in line: String) -> String {
        if line.contains("property refuted") { return "invariantCheck" }
        if line.contains("not the invariant check") { return "subjectCode" }
        if line.contains("cause unattributed") { return "unattributable" }
        return "?"
    }

    private static func survey(_ corpus: Corpus) async throws -> String {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("trap-attribution-census")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: corpus.module,
            fromSourcesDirectory: fixtures.appendingPathComponent(corpus.fixture),
            into: parent
        )
        return try await VerifyInteractionSurvey.run(
            target: corpus.module,
            familyFilter: corpus.family,
            sequenceCount: 128,
            workingDirectory: root
        )
    }

    static let fixtures: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
    }()
}
