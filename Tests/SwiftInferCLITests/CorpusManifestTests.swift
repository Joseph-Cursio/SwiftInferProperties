import Foundation
import Testing

@testable import SwiftInferCLI

/// The corpus manifest is only worth having if it cannot quietly stop describing the corpus.
///
/// ## What each group of arms is for
///
/// **Both directions, and they fail differently.** A measurement naming a record that does not
/// exist is a dangling pointer and is loud the first time anyone follows it. A retained run in
/// `fixtures/verify-runs/` that no entry names is **silent** — it sits there looking like a
/// baseline, gets diffed against, and carries no remote, no target binding and no reason for
/// existing. That is the direction that matters, and it is the same asymmetry
/// `SubprocessBatchCoverageTests` records for the Makefile batches: matched-but-unbatched never
/// runs, `.subprocess`-but-unmatched runs in the fast path.
///
/// **Every measurement points at where its result lives.** That is the discipline the whole
/// file exists for: a measurement with nowhere to point is one whose result was discarded, and
/// four full surveys were lost exactly that way.
///
/// **A known-wrong member must say what is expected of it.** Every other member is code
/// believed correct, where a clean sweep is the weak-but-correct outcome; a `backtest` with no
/// recorded expectation is just a run, and gives recall no denominator.
///
/// **The population is asserted.** Every other arm here is vacuous over an empty manifest.
@Suite("The corpus manifest describes the corpus, in both directions")
struct CorpusManifestTests {

    static let repositoryRoot = URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func manifest() throws -> CorpusManifest {
        try CorpusManifest.load(repositoryRoot: repositoryRoot)
    }

    static func allMeasurements() throws -> [(CorpusManifest.Entry, CorpusManifest.Measurement)] {
        try manifest().corpora.flatMap { entry in
            entry.measurements.map { (entry, $0) }
        }
    }

    // MARK: - The denominator

    @Test("The committed manifest loads and lists corpora")
    func manifestIsNotEmpty() throws {
        let manifest = try Self.manifest()
        #expect(manifest.schemaVersion == CorpusManifest.currentSchemaVersion)
        #expect(
            !manifest.corpora.isEmpty,
            """
            An empty corpus manifest makes every other arm in this suite vacuous, and would \
            report a clean sweep having measured nothing.
            """
        )
        #expect(!(try Self.allMeasurements()).isEmpty, "no measurements — arms below are vacuous")
    }

    @Test("Corpus ids are unique — a measurement cites one by id")
    func identifiersAreUnique() throws {
        let identifiers = try Self.manifest().identifiers
        #expect(Set(identifiers).count == identifiers.count, "duplicate id in \(identifiers)")
    }

    // MARK: - Manifest → disk

    @Test("Every measurement points at a record that exists")
    func everyMeasurementHasARecord() throws {
        for (entry, measurement) in try Self.allMeasurements() {
            #expect(!measurement.record.isEmpty, "corpus '\(entry.id)' has a recordless measurement")
            let url = Self.repositoryRoot.appendingPathComponent(measurement.record)
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                """
                corpus '\(entry.id)' points at \(measurement.record), which is not there. A \
                measurement with nowhere to point is one whose result was discarded.
                """
            )
        }
    }

    @Test("Every answer key that is cited exists")
    func everyAnswerKeyExists() throws {
        for (entry, measurement) in try Self.allMeasurements() {
            guard let key = measurement.answerKey else { continue }
            let url = Self.repositoryRoot.appendingPathComponent(key)
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                "corpus '\(entry.id)' cites answer key \(key), which is not there"
            )
        }
    }

    /// The binding that makes a retained run reproducible: the file has to be a run of the
    /// target the entry claims. A mis-filed run is otherwise indistinguishable from a correct
    /// one until someone diffs two different subjects.
    @Test("A retained survey stream is a run of the target the entry claims")
    func retainedStreamMatchesItsTarget() throws {
        for (entry, measurement) in try Self.allMeasurements() {
            guard measurement.record.hasSuffix(".json"),
                  measurement.record.contains("verify-runs") else { continue }
            let url = Self.repositoryRoot.appendingPathComponent(measurement.record)
            let retained = try RetainedSurveyRun.read(from: url)
            #expect(
                retained.target == entry.target,
                """
                \(measurement.record) is a run of '\(retained.target)' but corpus \
                '\(entry.id)' claims target '\(entry.target ?? "nil")'
                """
            )
        }
    }

    /// Deterministic only for checkouts committed to this repository, so it is scoped to those
    /// rather than skipped — an external clone may be absent, an in-repo fixture never is.
    @Test("An in-repo corpus names a target its own Package.swift declares")
    func inRepoTargetsAreReal() throws {
        var checked = 0
        for entry in try Self.manifest().corpora {
            guard let target = entry.target else { continue }
            let root = entry.resolvedPath(repositoryRoot: Self.repositoryRoot)
            guard root.path.hasPrefix(Self.repositoryRoot.path) else { continue }
            let manifestFile = root.appendingPathComponent("Package.swift")
            guard let text = try? String(contentsOf: manifestFile, encoding: .utf8) else { continue }
            checked += 1
            #expect(
                text.contains("\"\(target)\""),
                "corpus '\(entry.id)' names target '\(target)', absent from \(manifestFile.path)"
            )
        }
        #expect(checked > 0, "no in-repo corpus was checked — this arm would be vacuous")
    }

    // MARK: - Disk → manifest (the silent direction)

    @Test("Every retained run on disk is registered by exactly one corpus")
    func everyRetainedRunIsRegistered() throws {
        let directory = Self.repositoryRoot.appendingPathComponent("fixtures/verify-runs")
        let onDisk = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        #expect(!onDisk.isEmpty, "no retained runs found — this arm would be vacuous")

        let registered = try Self.allMeasurements()
            .map { URL(fileURLWithPath: $0.1.record).lastPathComponent }
        for file in onDisk {
            let count = registered.filter { $0 == file }.count
            #expect(
                count == 1,
                """
                fixtures/verify-runs/\(file) is registered \(count) time(s) in \
                \(CorpusManifest.relativePath). An unregistered run carries no remote, no \
                revision binding and no reason for existing — it looks like a baseline and \
                cannot be reproduced.
                """
            )
        }
    }

    // MARK: - Pins

    /// A recorded revision is a full 40-character SHA — or absent, which is its own state.
    ///
    /// **`nil` is exempted rather than forbidden, and the arm below is why.** A measurement whose
    /// subject revision cannot be established was previously unrepresentable, so it was written as
    /// a SHA-shaped string resolving nowhere — which is indistinguishable from a stale clone and
    /// sends a reader to `git fetch` forever. Absence says the true thing.
    @Test("Every recorded revision is a full 40-character SHA, or explicitly absent")
    func revisionsAreFullLength() throws {
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        for (entry, measurement) in try Self.allMeasurements() {
            guard let revision = measurement.revision else { continue }
            #expect(
                revision.count == 40,
                """
                corpus '\(entry.id)' pins '\(revision)' — a short SHA cannot be \
                resolved in a clone that does not already hold the object
                """
            )
            #expect(
                CharacterSet(charactersIn: revision).isSubset(of: hex),
                "corpus '\(entry.id)' pins a non-hex revision '\(revision)'"
            )
        }
    }

    /// A `nil` revision must SAY it is unrecoverable, in the arm a reader sees.
    ///
    /// Without this, `nil` is cheaper than a real pin: someone registering a measurement they
    /// cannot be bothered to pin gets silence instead of a short-SHA failure, and the field
    /// designed to record a known loss becomes the field used to record not looking.
    @Test("An absent revision explains itself in the arm")
    func absentRevisionsAreExplained() throws {
        var seen = 0
        for (entry, measurement) in try Self.allMeasurements() where measurement.revision == nil {
            seen += 1
            #expect(
                measurement.arm.uppercased().contains("REVISION UNRECOVERABLE"),
                """
                corpus '\(entry.id)' records no revision but its arm does not say \
                REVISION UNRECOVERABLE — absence must be a stated finding, not an omission
                """
            )
        }
        // Asserting the denominator: if this ever reaches zero the arm above is vacuous, and a
        // vacuous guard reads exactly like a satisfied one. `scanIsNotEmpty`, again.
        #expect(seen > 0, "no corpus records an absent revision — is this arm still reachable?")
    }

    @Test("At most one baseline per corpus — the baseline is what sets the pin")
    func atMostOneBaseline() throws {
        for entry in try Self.manifest().corpora {
            let baselines = entry.measurements.filter { $0.kind == "baseline" }
            #expect(
                baselines.count <= 1,
                "corpus '\(entry.id)' lists \(baselines.count) baselines; a diff needs one"
            )
        }
    }

    @Test("A frozen measurement says what re-running would destroy")
    func frozenMeasurementsExplainTheirExemption() throws {
        for (entry, measurement) in try Self.allMeasurements() {
            #expect(
                ["baseline", "frozen", "backtest", "census"].contains(measurement.kind),
                "corpus '\(entry.id)' has measurement kind '\(measurement.kind)'"
            )
            guard measurement.kind == "frozen" else { continue }
            #expect(
                measurement.frozenBecause?.isEmpty == false,
                """
                \(measurement.record) is exempt from refresh and does not say what re-running \
                would destroy — an unexplained exemption is indistinguishable from an oversight
                """
            )
        }
    }

    // MARK: - Known-wrong members

    @Test("A backtest records what the tool is supposed to find")
    func backtestsCarryAnExpectation() throws {
        var backtests = 0
        for (entry, measurement) in try Self.allMeasurements() {
            guard measurement.kind == "backtest" else { continue }
            backtests += 1
            #expect(
                measurement.expectedOutcome?.isEmpty == false,
                """
                corpus '\(entry.id)' registers known-wrong code with no expected outcome. \
                Without one it is just a run, and recall keeps having no denominator.
                """
            )
        }
        #expect(
            backtests > 0,
            """
            no backtest is registered, so nothing in this corpus is known-wrong and a clean \
            sweep remains indistinguishable from a blind instrument
            """
        )
    }

    // MARK: - Reach

    @Test("Exactly one of target / sources, and an app is reached by sources")
    func reachIsUnambiguous() throws {
        for entry in try Self.manifest().corpora {
            let hasTarget = entry.target != nil
            let hasSources = entry.sources != nil
            #expect(
                hasTarget != hasSources,
                """
                corpus '\(entry.id)' sets \(hasTarget && hasSources ? "both" : "neither") of \
                target / sources
                """
            )
            if entry.kind == "app" {
                #expect(hasSources, "app corpus '\(entry.id)' must be reached by sources")
            }
            #expect(
                ["package", "sibling", "app", "mutant"].contains(entry.kind),
                "corpus '\(entry.id)' has kind '\(entry.kind)'"
            )
        }
    }

    @Test("Every corpus says why it is in the corpus, and where it comes from")
    func everyCorpusStatesItsReason() throws {
        for entry in try Self.manifest().corpora {
            #expect(!entry.why.isEmpty, "corpus '\(entry.id)' does not say what it is for")
            #expect(!entry.remote.isEmpty, "corpus '\(entry.id)' names no remote")
        }
    }

    // MARK: - Apparatuses

    /// The registry exists partly to replace four disjoint corpus lists, so it has to actually
    /// carry more than one apparatus — a manifest describing only `prove-then-show` would have
    /// re-created the split it was built to close.
    @Test("More than one apparatus is represented, and each selects a non-empty set")
    func apparatusesAreRealAndSelective() throws {
        let manifest = try Self.manifest()
        let names = manifest.apparatuses
        #expect(names.count > 1, "only \(names) — the registry still describes one apparatus")
        for name in names {
            #expect(
                !manifest.corpora(measuredBy: name).isEmpty,
                "apparatus '\(name)' selects nothing, so the filter would report a false gap"
            )
        }
    }
}
