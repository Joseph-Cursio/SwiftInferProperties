import Foundation
import SwiftInferCore

/// A `prove-then-show` / `verify --all-from-index` run, retained whole so a later run can be
/// diffed against it **row by row**.
///
/// ## Why this exists
///
/// Four full surveys of `SwiftInferCore` are on record
/// (`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §8, §9 arm G, §10.10, §11). Every
/// one produced a per-pick record carrying its identity, bucket and decline *cause*. Not one
/// of those streams survives, so no two passes can be compared at row level — §11.1 had to
/// record "at least one earlier pick left the corpus or changed bucket, and saying which
/// would need the previous run's row list, which this document does not record."
///
/// That is not a missing feature so much as a discarded artifact, and the repo has now
/// diagnosed it three times: `fixtures/whole-corpus-survey/`'s README records a run that
/// **overwrote the file it was being compared against**, and `VerifyEvidence.corpusProvenance`
/// exists because "two survey streams taken a week apart are not comparable without this."
/// Both fixes made a single run more self-describing. Neither made the run *survive*.
///
/// ## Why the survey stream and not `verify-evidence.json`
///
/// The persisted evidence store is **lossy in exactly the bucket that matters**:
/// `architecturalCoveragePending` collapses to `measuredError` on write, as
/// `VerifyCommand+AllFromIndex.swift:23` states in as many words. Unverifiable is where the
/// interesting movement has been — §9.3's nine syntax-node rows, §9.7's re-attribution,
/// §11.3's two `BodySignalVisitor` rows — so a diff built on the store could not have
/// answered a single one of those questions. `SurveyRecord` is the canonical measurement
/// vocabulary and keeps the five-way outcome plus `outcomeDetail`, the cause string.
///
/// ## Why this is committed to `fixtures/`
///
/// Because gitignored is how the last four vanished. `.swiftinfer/` is swept by
/// `make clean-temp` by design, and a comparison baseline that a routine cleanup deletes is
/// not a baseline. A run is ~50 KB of JSON for ~160 picks.
struct RetainedSurveyRun: Codable, Sendable {

    /// Bumped only on a **breaking** change to this envelope. Additive optional fields do not
    /// need it (synthesized `Codable` uses `decodeIfPresent` for optionals), which is the same
    /// argument `VerifyEvidence.excludedActionCount` makes for not bumping.
    static let currentSchemaVersion = 1

    let schemaVersion: Int

    /// Free text naming what this run *is* — the arm, not the file. Read by a human comparing
    /// two runs months apart, so "SwiftInferCore @ fdae49f, kit 3.28.0" beats "run 4".
    let label: String

    let capturedAt: Date

    /// The target surveyed, so a diff can refuse to compare two different subjects.
    let target: String

    /// `CorpusProvenance.describe` of the package root — `<path> @ <sha>`, plus
    /// `(uncommitted changes)` when the tree is dirty, or an explicit "not a git checkout"
    /// when there is no revision to record.
    ///
    /// **This, and not `swiftInferVersion`, is what identifies the code a run was taken
    /// against.** §10.2 measured the version string failing at both ends: all 349 records in a
    /// contaminated store read `1.148.0` across ~40 commits, and the same field *varied* for an
    /// unrelated reason (`(unattributable build)`). A field that fails to move when the code
    /// moves and moves when it does not cannot date a measurement.
    let subjectRevision: String

    /// Kept despite the paragraph above, because it dates the *instrument* rather than the
    /// subject and the two really are different questions. Never used as the comparison key.
    let swiftInferVersion: String

    /// Pre-verify tier per identity hash, as read off the index the run built. Retained
    /// because the renderer's Expected-to-hold / Disproven split is computed from it, so a
    /// diff that lacked it could not reproduce the buckets a reader actually saw.
    let tiersByIdentity: [String: String]

    let records: [SwiftInferCommand.Verify.SurveyRecord]

    // MARK: - Reading and writing

    /// ISO8601 dates and sorted keys, so a re-run that changes nothing produces a
    /// byte-identical file and `git diff` stays legible. Without `.sortedKeys` the tier map
    /// reorders per run and every retained run looks changed.
    private static func encoder() -> JSONEncoder {
        let coder = JSONEncoder()
        coder.dateEncodingStrategy = .iso8601
        coder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return coder
    }

    private static func decoder() -> JSONDecoder {
        let coder = JSONDecoder()
        coder.dateDecodingStrategy = .iso8601
        return coder
    }

    static func read(from url: URL) throws -> Self {
        try decoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Self.encoder().encode(self).write(to: url, options: .atomic)
    }

    /// Everything about a run that is not the records themselves.
    ///
    /// Grouped rather than passed as five loose arguments because they travel together and are
    /// all easy to transpose — `label` and `target` are both `String`, and swapping them
    /// silently mislabels an artifact meant to outlive the session that wrote it.
    struct Context {
        let label: String
        let target: String
        let packageRoot: URL
        /// Injected rather than read from the clock so a test can pin it; every production
        /// caller passes `Date()`.
        let capturedAt: Date
    }

    /// Build an envelope from a finished survey.
    static func capturing(
        records: [SwiftInferCommand.Verify.SurveyRecord],
        tiers: [String: Tier],
        context: Context
    ) -> Self {
        let label = context.label
        let target = context.target
        let packageRoot = context.packageRoot
        let capturedAt = context.capturedAt
        return Self(
            schemaVersion: currentSchemaVersion,
            label: label,
            capturedAt: capturedAt,
            target: target,
            subjectRevision: CorpusProvenance.describe(packageRoot),
            swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion,
            tiersByIdentity: tiers.mapValues { $0.rawValue },
            records: records
        )
    }
}
