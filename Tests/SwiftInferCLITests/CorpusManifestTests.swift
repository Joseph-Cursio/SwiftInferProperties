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

    /// A corpus must be reachable, and the two fields answer different questions.
    ///
    /// **This asserted EXACTLY one until 2026-08-15, and that was too strong.** The rule encoded
    /// the `prove-then-show` model — a package is reached by `target`, an app by `sources` — and
    /// a third case exists: a package whose code is not under `Sources/<target>`.
    /// `swift-collections` is the witness. `Collections` is a real, buildable target and the
    /// right thing for a survey to compile; it is also a **pure re-export umbrella** — five
    /// `… reexports.swift` files holding typealiases and **zero declarations** — so a census
    /// pointed at it scans real files and finds no API. It reported `0 rows` beside corpora
    /// reporting four figures, which is the shape of a dead catalog rather than of a
    /// misconfigured path.
    ///
    /// So `target` is **what to build** and `sources` is **what to scan**, they may both be
    /// present, and at least one must be. What is still forbidden is *neither*, which leaves the
    /// corpus unreachable by either route.
    @Test("A corpus is reachable by target, by sources, or by both — never by neither")
    func reachIsUnambiguous() throws {
        for entry in try Self.manifest().corpora {
            let hasTarget = entry.target != nil
            let hasSources = entry.sources != nil
            #expect(
                hasTarget || hasSources,
                "corpus '\(entry.id)' sets neither target nor sources, so nothing can reach it"
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
