import Foundation

/// The committed registry of subject codebases the toolchain is measured against.
///
/// ## Why this exists
///
/// `fixtures/verify-runs/` already solves *a run must survive*. It does not solve **a run must
/// be reproducible**, and the four runs banked there prove the difference: every one records
/// its `subjectRevision` as
/// `/tmp/claude-501/…/scratchpad/grdb-native @ b83108d10 (uncommitted changes)`. The revision
/// is real; the path is a scratchpad directory belonging to a session that has ended, and
/// nothing anywhere records that `b83108d10` is a commit of `groue/GRDB.swift`. Three of the
/// four also say `(uncommitted changes)`, so even the revision does not fully name the code.
///
/// The artifact built expressly to outlive its session says *where* it ran, and that place is
/// gone. Those subjects are re-derivable today only because nobody has run `git pull` on the
/// clones since — which is luck, not provenance.
///
/// ## The revision belongs to the MEASUREMENT, not to the corpus
///
/// A pinned revision here is not *the version we intend to test*. It is **the version this
/// measurement was taken against** — a fact about work already done, in a repo whose standing
/// rule is that diagnoses do not expire and measurements do. A corpus nobody has measured has
/// no revision, and says so, rather than carrying an aspiration that reads like a pin.
///
/// That framing is what makes the drift check meaningful: a checkout sitting off-pin does not
/// mean *update the manifest*, it means *a diff taken here will mix a change in the subject
/// with a change in the tool*, which is the one confound `survey-diff` exists to separate.
///
/// ## One list, four apparatuses
///
/// `measurements` is deliberately **not** a list of retained survey runs. `prove-then-show` is
/// one of at least four things that have been pointed at these subjects — the others being the
/// census scripts, the kit-suite backtest and the swift.org study — and each kept its own
/// disjoint corpus list, so "the corpus" meant something different depending on which tool you
/// had run. Modelling only survey runs would have re-created that split inside the fix.
///
/// A measurement therefore names its `apparatus` and points at its `record`, whether that
/// record is a retained JSON stream or the findings doc that is the only place a census
/// survives.
struct CorpusManifest: Codable, Sendable {

    /// Bumped only on a **breaking** change to this envelope. Additive optional fields do not
    /// need it (synthesized `Codable` uses `decodeIfPresent` for optionals), which is the same
    /// argument `RetainedSurveyRun.currentSchemaVersion` makes. Bumped to 2 when `runs` became
    /// `measurements` and the subject kinds widened past "third-party SwiftPM library".
    static let currentSchemaVersion = 2

    /// Repo-relative location, so every caller names it the same way.
    static let relativePath = "fixtures/corpora/manifest.json"

    let schemaVersion: Int
    let corpora: [Entry]

    /// One subject codebase.
    struct Entry: Codable, Sendable {

        /// Stable slug, and the handle `prove-then-show --corpus <id>` takes. Never renamed
        /// once a measurement cites it.
        let id: String

        /// What a human calls the subject — the repository, not the target.
        let subject: String

        /// How this subject is reached, and it is not decoration — the four kinds need
        /// genuinely different handling and were each set up by hand, uncorded, before this.
        ///
        /// - `package` — a third-party SwiftPM package, reached by `target`.
        /// - `sibling` — a package in this toolchain. Same mechanics; different because the
        ///   cross-repo seam is the thing nothing else checks, and its remote is ours.
        /// - `app` — no SwiftPM target to resolve, reached by `sources`. An Xcode project.
        /// - `mutant` — code that is deliberately WRONG. See `Measurement.expectedOutcome`.
        let kind: String

        /// The SwiftPM target surveyed. One per entry: two targets of one package are two
        /// measurements, and folding them into a row would make the pin ambiguous.
        ///
        /// Exactly one of `target` / `sources` is set, and `CorpusManifestTests` asserts it.
        let target: String?

        /// Path *within the checkout* to a source directory, for a subject with no manifest to
        /// resolve a target against. The `--sources` escape hatch, which is how every user of
        /// an Xcode project meets this tool.
        let sources: String?

        /// Where the subject comes from. The authority — `localPath` is only a hint about
        /// where a clone was last seen.
        let remote: String

        /// Resolution hint, `~`-relative or repo-relative. **Deliberately not authoritative**:
        /// this project is worked from two machines, so a path that resolves on one and not
        /// the other is the normal case rather than an error.
        let localPath: String

        /// `control` (home turf, the ceiling other numbers are read against) or `unfamiliar`
        /// (code the catalog was never tuned against). Free text; nothing branches on it.
        let role: String

        /// **Why this subject earns a place in the corpus.** Not decoration: a corpus that
        /// cannot say what each member is for grows by accretion, and several entries here are
        /// in it because they exposed an instrument defect no other subject could.
        let why: String

        /// Every measurement taken against this subject, by any apparatus. Empty is legal and
        /// means *registered, never measured* — which is how a subject is enqueued.
        let measurements: [Measurement]
    }

    /// One measurement, and the revision it was taken against.
    struct Measurement: Codable, Sendable {

        /// Which machinery produced this. `prove-then-show`, `discover-ab`, `census`,
        /// `kit-suite-backtest`, `swiftorg-study`, `road-test`.
        let apparatus: String

        /// - `baseline` — refreshed when a sweep confirms a newer commit reproduces it, and the
        ///   thing a later run is diffed against. At most one per entry: it sets the pin.
        /// - `frozen` — never refreshed, because re-running would destroy what it evidences.
        /// - `backtest` — taken at a revision chosen *because* a fix landed after it, so the
        ///   subject is known-wrong there. Must carry `expectedOutcome`.
        /// - `census` — a counted sweep whose record is a findings doc, not an artifact.
        let kind: String

        /// Full 40-character SHA. **Full, not short**: `b83108d10` is nine characters, which is
        /// neither a git default nor collision-proof, and a short SHA cannot be resolved in a
        /// clone that does not already contain the object.
        let revision: String

        /// ISO date, as a plain string — this is read by people, and re-encoding a `Date`
        /// through a formatter is a way to change a committed file by accident.
        let takenOn: String

        /// Which arm this is, in a line.
        let arm: String

        /// Repo-relative path to where this measurement's result actually lives — a retained
        /// stream, a findings doc, a fixture README.
        ///
        /// **Required, and that is the discipline.** A measurement with nowhere to point is one
        /// whose result was discarded, which is the failure this whole file exists about.
        let record: String

        /// Set only on `frozen`, stating what re-running would destroy. An exemption from
        /// refresh has to say why at the point of exemption, or it is indistinguishable from an
        /// oversight.
        let frozenBecause: String?

        /// **What the tool is supposed to find here** — required on `backtest`, and the whole
        /// point of registering known-wrong code.
        ///
        /// Every other member of this corpus is code believed CORRECT, so a clean sweep is the
        /// weak-but-correct outcome and there is no denominator for recall. A member whose
        /// expected verdict is written down converts "0 defects found" from an unfalsifiable
        /// result into a checkable one. It records the MISSES too: the projection-mutant arm is
        /// registered precisely because the emitted suites did not catch it.
        let expectedOutcome: String?

        /// A frozen answer key committed before the measurement, where one exists. The
        /// strongest form of `expectedOutcome`, and the reason it is a pointer rather than a
        /// copy: `fixtures/swiftorg-study/q2-answer-key.json` was committed *before* any
        /// `discover` run so the tool could not grade its own homework, and re-encoding it here
        /// would create a second copy to drift.
        let answerKey: String?
    }
}

// MARK: - Loading

extension CorpusManifest {

    enum LoadError: Error, CustomStringConvertible {
        case unreadable(path: String, underlying: Error)
        case unsupportedSchema(found: Int, supported: Int)

        var description: String {
            switch self {
            case let .unreadable(path, underlying):
                return "could not read the corpus manifest at '\(path)': \(underlying)"

            case let .unsupportedSchema(found, supported):
                return "corpus manifest declares schemaVersion \(found); this build "
                    + "understands \(supported)"
            }
        }
    }

    /// Load the manifest from a repo root.
    static func load(repositoryRoot: URL) throws -> Self {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        let manifest: Self
        do {
            manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        } catch {
            throw LoadError.unreadable(path: url.path, underlying: error)
        }
        guard manifest.schemaVersion == currentSchemaVersion else {
            throw LoadError.unsupportedSchema(
                found: manifest.schemaVersion, supported: currentSchemaVersion
            )
        }
        return manifest
    }

    /// The entry with this id, or `nil`.
    func entry(id: String) -> Entry? {
        corpora.first { $0.id == id }
    }

    /// Every id, in manifest order — for an error message that lists what the caller could
    /// have typed instead.
    var identifiers: [String] {
        corpora.map(\.id)
    }

    /// Every apparatus named by any measurement, sorted. Used to validate `--apparatus` and to
    /// tell a caller what the corpus has actually been put through.
    var apparatuses: [String] {
        Set(corpora.flatMap(\.measurements).map(\.apparatus)).sorted()
    }

    /// Entries measured by `apparatus`, which is the question each of the four disjoint corpus
    /// lists used to answer on its own.
    func corpora(measuredBy apparatus: String) -> [Entry] {
        corpora.filter { entry in
            entry.measurements.contains { $0.apparatus == apparatus }
        }
    }
}

// MARK: - Path resolution

extension CorpusManifest.Entry {

    /// Expand `localPath` against a repo root.
    ///
    /// `~` and `~/…` expand to the home directory; anything else relative resolves against
    /// `repositoryRoot`, which is what makes `"."` mean *this package* for the self-dogfood
    /// entry rather than the process's working directory.
    ///
    /// `~user` is deliberately unsupported and falls through to the relative branch, where it
    /// resolves to nothing and reports as a missing checkout. Expanding another user's home is
    /// not a thing a corpus path should be doing, and failing visibly beats resolving it.
    func resolvedPath(repositoryRoot: URL) -> URL {
        if localPath == "~" || localPath.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let remainder = String(localPath.dropFirst(localPath == "~" ? 1 : 2))
            return remainder.isEmpty
                ? home.standardizedFileURL
                : home.appendingPathComponent(remainder).standardizedFileURL
        }
        if localPath.hasPrefix("/") {
            return URL(fileURLWithPath: localPath).standardizedFileURL
        }
        return repositoryRoot.appendingPathComponent(localPath).standardizedFileURL
    }

    /// The measurement that sets this entry's pin, if any.
    ///
    /// Only a `baseline` does. A `census` or `backtest` records the revision **it** was taken
    /// at, which is a different claim — a backtest is pinned to a commit chosen because the
    /// code is broken there, and treating that as the pin would report the subject as having
    /// "moved off" the moment anyone checked out a working version.
    var baselineMeasurement: CorpusManifest.Measurement? {
        measurements.first { $0.kind == "baseline" }
    }

    /// Whether `prove-then-show --corpus` can reach this subject at all.
    ///
    /// An `app` entry has no SwiftPM target, and the survey resolves one unconditionally. This
    /// is a refusal rather than a silent empty scan, which is the failure mode
    /// `ProveThenShowSourcesReachTests` records for the layout resolver.
    var isSurveyable: Bool {
        target != nil
    }

    /// How this subject is reached, for a label or a report line. Never a bare `Optional`
    /// description — a run label is read by a human months later and `Optional("GRDB")` in a
    /// committed artifact is a defect nobody notices until they are trying to reproduce it.
    var reachLabel: String {
        target ?? sources.map { "sources:\($0)" } ?? "unreachable"
    }
}
