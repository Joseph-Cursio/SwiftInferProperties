import Foundation
import Testing

@testable import SwiftInferCLI

/// The pin arms of `CorpusManifestTests`, split out when the suite passed `type_body_length`.
///
/// **They belong together and are the natural cut.** Every arm here asks the same question from a
/// different side: *does this revision name the code the measurement actually ran against?* The
/// shape-only checks (a full 40-char SHA, at most one baseline) cannot answer it — a revision can
/// be perfectly well-formed, resolve cleanly, and still be the wrong one, which is exactly how
/// five entries came to pin a commit dated after their own measurement.
///
/// Kept as an extension rather than a second `@Suite` so the arms stay reported under the suite
/// whose invariant they enforce, and so `Self.manifest()` / `Self.allMeasurements()` /
/// `Self.repositoryRoot` are shared rather than duplicated — a second copy of the loader is a
/// second thing to keep in step with the file it reads.
extension CorpusManifestTests {
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

    /// The commit date of `revision` in the checkout at `root`, as `YYYY-MM-DD`, or `nil` when
    /// the checkout cannot answer — absent, not a git repository, or simply lacking the object.
    ///
    /// **`%cs` (committer date, short) rather than `%as` (author date).** A rebased or
    /// cherry-picked commit keeps its author date and takes a new committer date; the question
    /// here is *when did this land in the tree a measurement could have run against*, which is
    /// the committer date. Author date would let a rebased commit read as older than it is and
    /// slip past this arm.
    private static func commitDate(of revision: String, at root: URL) -> String? {
        guard let data = DrainedProcess.standardOutputViaEnv(
            ["git", "-C", root.path, "log", "-1", "--format=%cs", revision]
        ) else { return nil }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
    }

    /// A measurement cannot have been taken against code that did not exist yet.
    ///
    /// **Five entries failed this when it was written**, and the shape is one mistake: a revision
    /// filled in from whatever was checked out when the *registry* was written, rather than read
    /// off the measurement. Three shared this repository's HEAD from registration day. That is the
    /// same error as the one `swiftlint-rule-studio` records — except those SHAs **resolve**, which
    /// is worse, because a resolving SHA reads as a verified one and `cat-file` says nothing
    /// against it.
    ///
    /// So this is the arm that catches the class: not *does the revision exist* but *could this
    /// measurement have been taken against it*. One `git log -1 --format=%cs` per row.
    ///
    /// **A checkout that cannot answer is skipped, not failed** — corpora live outside this
    /// repository and a clone absent on this machine is the ordinary two-machine case, which
    /// `fixtures/corpora/README.md` calls out as its own state. The denominator arm below is what
    /// stops that exemption quietly emptying the test.
    @Test("No revision postdates the measurement said to have used it")
    func revisionsDoNotPostdateTheirMeasurement() throws {
        var checked = 0
        for (entry, measurement) in try Self.allMeasurements() {
            guard let revision = measurement.revision else { continue }
            let root = entry.resolvedPath(repositoryRoot: Self.repositoryRoot)
            guard let committed = Self.commitDate(of: revision, at: root) else { continue }
            checked += 1
            #expect(
                committed <= measurement.takenOn,
                """
                corpus '\(entry.id)' pins '\(String(revision.prefix(7)))' committed \
                \(committed), but says the measurement was taken \(measurement.takenOn) — \
                a measurement cannot have run against code that did not exist yet, so this \
                revision is not the one it used
                """
            )
        }
        #expect(
            checked > 0,
            """
            no corpus revision could be dated — every checkout is missing, so this arm proved \
            nothing. It must not read as a pass.
            """
        )
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
}
