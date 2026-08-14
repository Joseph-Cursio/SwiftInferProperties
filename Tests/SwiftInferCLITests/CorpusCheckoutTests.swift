import Foundation
import Testing

@testable import SwiftInferCLI

/// Resolving a corpus checkout, and the three-way answer that keeps a missing clone out of the
/// pass column.
///
/// ## Why most of these arms are negative
///
/// The easy shape is two-valued — at pin, or not — and it is wrong here for a reason that is
/// structural rather than fussy: the corpora live outside this repository, this project is
/// worked from two machines, and a clone present on one and absent on the other is the
/// ordinary case. Under a two-valued verdict a machine holding none of them reports every
/// corpus as fine. So `.uncheckable` exists, nothing collapses into it, and the arms below
/// mostly assert what a state is **not**.
///
/// ## No subprocess, and no `git init`
///
/// The one thing needing a real checkout is `.resolved`, and this repository is one — so the
/// arm that wants a live revision points at itself rather than building a scratch repo, and
/// asserts the *shape* (a full-length head) rather than a value that changes every commit.
///
/// Every verdict arm is fed a synthetic `CorpusCheckout` instead. That is not a shortcut: an
/// at-pin arm driven through a real checkout would have to pin whatever HEAD happens to be,
/// making it pass whenever the comparison is a tautology, and a dirty-tree arm would depend on
/// whether the developer's working tree is dirty at the moment the suite runs.
@Suite("A corpus checkout resolves three ways, and cannot-check is not a pass")
struct CorpusCheckoutTests {

    static let repositoryRoot = URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func entry(
        id: String = "probe",
        localPath: String,
        measurements: [CorpusManifest.Measurement] = []
    ) -> CorpusManifest.Entry {
        CorpusManifest.Entry(
            id: id,
            subject: "Probe",
            kind: "package",
            target: "ProbeTarget",
            sources: nil,
            remote: "https://example.invalid/probe.git",
            localPath: localPath,
            role: "unfamiliar",
            why: "a fixture",
            measurements: measurements
        )
    }

    static func measurement(revision: String, kind: String = "baseline") -> CorpusManifest.Measurement {
        CorpusManifest.Measurement(
            apparatus: "prove-then-show",
            kind: kind,
            revision: revision,
            takenOn: "2026-08-14",
            arm: "fixture",
            record: "fixtures/verify-runs/probe.json",
            frozenBecause: nil,
            expectedOutcome: nil,
            answerKey: nil
        )
    }

    static let absentRevision = String(repeating: "0", count: 40)

    // MARK: - Reading the checkout

    @Test("A path with nothing at it reads as missing, and the verdict is uncheckable")
    func missingCheckoutCannotBeChecked() {
        let subject = Self.entry(localPath: "/nonexistent/corpus/probe")
        let checkout = CorpusCheckout.read(subject, repositoryRoot: Self.repositoryRoot)
        guard case .missing = checkout else {
            Issue.record("expected .missing, got \(checkout)")
            return
        }
        let pin = CorpusPin.verdict(entry: subject, checkout: checkout)
        #expect(pin == .uncheckable)
        #expect(pin != .atPin(dirty: false), "a missing clone must never read as at-pin")
        #expect(!pin.isComparable)
    }

    @Test("A directory that is not a git checkout reads as untracked, not as at-pin")
    func untrackedCheckoutCannotBeChecked() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-untracked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let subject = Self.entry(localPath: directory.path)
        let checkout = CorpusCheckout.read(subject, repositoryRoot: Self.repositoryRoot)
        guard case .untracked = checkout else {
            Issue.record("expected .untracked, got \(checkout)")
            return
        }
        #expect(CorpusPin.verdict(entry: subject, checkout: checkout) == .uncheckable)
    }

    @Test("A real checkout resolves, and reports a revision")
    func realCheckoutResolves() {
        let subject = Self.entry(localPath: Self.repositoryRoot.path)
        let checkout = CorpusCheckout.read(subject, repositoryRoot: Self.repositoryRoot)
        guard case let .resolved(_, head, _) = checkout else {
            Issue.record("expected .resolved for this repository, got \(checkout)")
            return
        }
        #expect(head.count == 40, "head '\(head)' is not a full SHA")
    }

    // MARK: - The verdict

    @Test("An entry with no baseline has no pin, and that is not a pass")
    func noBaselineIsNotAPass() {
        let subject = Self.entry(localPath: Self.repositoryRoot.path)
        let checkout = CorpusCheckout.resolved(path: "/x", head: Self.absentRevision, dirty: false)
        let pin = CorpusPin.verdict(entry: subject, checkout: checkout)
        #expect(pin == .noBaseline)
        #expect(
            !pin.isComparable,
            "there is nothing to compare against, which must not count as agreement"
        )
    }

    /// Both answers are true for a corpus that is neither cloned nor swept, and the precedence
    /// is a decision rather than an accident: `noBaseline` reads as *the tree is here, nobody
    /// has surveyed it*, which is the wrong instruction when there is no tree.
    @Test("An unreadable checkout outranks a missing baseline")
    func uncheckableOutranksNoBaseline() {
        let subject = Self.entry(localPath: "/nonexistent/corpus/probe")
        let pin = CorpusPin.verdict(entry: subject, checkout: .missing(path: "/nonexistent"))
        #expect(pin == .uncheckable)
        #expect(pin != .noBaseline)
    }

    @Test("A head matching the baseline is at pin; a dirty tree at the pin is not comparable")
    func atPinCarriesDirtinessSeparately() {
        let pinned = String(repeating: "a", count: 40)
        let subject = Self.entry(localPath: "/x", measurements: [Self.measurement(revision: pinned)])

        let clean = CorpusPin.verdict(
            entry: subject,
            checkout: .resolved(path: "/x", head: pinned, dirty: false)
        )
        #expect(clean == .atPin(dirty: false))
        #expect(clean.isComparable)

        let dirty = CorpusPin.verdict(
            entry: subject,
            checkout: .resolved(path: "/x", head: pinned, dirty: true)
        )
        #expect(dirty == .atPin(dirty: true))
        #expect(
            !dirty.isComparable,
            "a dirty tree measures uncommitted work that no revision names"
        )
    }

    @Test("A head other than the baseline reports both revisions")
    func movedOffNamesBothRevisions() {
        let pinned = String(repeating: "a", count: 40)
        let head = String(repeating: "b", count: 40)
        let subject = Self.entry(localPath: "/x", measurements: [Self.measurement(revision: pinned)])
        let pin = CorpusPin.verdict(
            entry: subject,
            checkout: .resolved(path: "/x", head: head, dirty: false)
        )
        #expect(pin == .movedOff(head: head, pinned: pinned, dirty: false))
        #expect(!pin.isComparable)
    }

    /// A `frozen` run is not a diff target, so it must not silently act as the pin.
    @Test("A frozen run is not a baseline")
    func frozenRunIsNotABaseline() {
        let subject = Self.entry(
            localPath: "/x",
            measurements: [Self.measurement(revision: String(repeating: "a", count: 40), kind: "frozen")]
        )
        #expect(subject.baselineMeasurement == nil)
        #expect(
            CorpusPin.verdict(
                entry: subject,
                checkout: .resolved(path: "/x", head: "a", dirty: false)
            ) == .noBaseline
        )
    }

    // MARK: - The report states its denominator

    @Test("A report containing an uncheckable corpus says so, and shortens its denominator")
    func reportStatesWhatItCouldNotRead() {
        let pinned = String(repeating: "a", count: 40)
        let good = Self.entry(id: "good", localPath: "/x", measurements: [Self.measurement(revision: pinned)])
        let gone = Self.entry(id: "gone", localPath: "/y", measurements: [Self.measurement(revision: pinned)])
        let text = CorpusStatusRenderer.render([
            CorpusStatus(
                entry: good,
                checkout: .resolved(path: "/x", head: pinned, dirty: false),
                pin: .atPin(dirty: false)
            ),
            CorpusStatus(entry: gone, checkout: .missing(path: "/y"), pin: .uncheckable)
        ])
        #expect(text.contains("2 corpora"))
        #expect(text.contains("1 checked"), "the denominator must shrink, not the claim")
        #expect(text.contains("1 at pin and clean"))
        #expect(text.contains("COULD NOT BE CHECKED"))
        #expect(
            text.contains("is not a corpus that agrees"),
            "an unread corpus has to be named as unread, not omitted"
        )
    }

    @Test("An empty manifest reports as measuring nothing, not as agreeing")
    func emptyReportIsNotACleanSweep() {
        let text = CorpusStatusRenderer.render([])
        #expect(text.contains("0 corpora"))
        #expect(text.contains("not a clean sweep"))
        #expect(!text.contains("at pin and clean"))
    }

    /// "No corpora" and "no corpora measured by this apparatus" send a reader to different
    /// places — one says the registry is empty, the other says a real coverage gap exists — so
    /// a filtered empty report names the filter that emptied it.
    @Test("A filtered empty report says which apparatus matched nothing")
    func filteredEmptyReportNamesTheFilter() {
        let text = CorpusStatusRenderer.render([], apparatus: "census")
        #expect(text.contains("census"))
        #expect(text.contains("gap in coverage"))
        #expect(!text.contains("the manifest lists no corpora"))
    }
}
