import Foundation
import Testing

@testable import SwiftInferCLI

/// `prove-then-show --corpus <id>` derives the tree, the target and the label from the
/// manifest, and the derived label carries its own caveats.
///
/// ## What is being guarded
///
/// The four runs in `fixtures/verify-runs/` were all labelled by hand at a shell, and every one
/// records a `subjectRevision` pointing into a scratchpad directory that no longer exists. A
/// hand-typed label is free text nobody validates: "GRDB @ b83108d10 native" is
/// indistinguishable from a label naming the wrong arm, and no reader six months out can tell.
///
/// So the arms that matter are the ones asserting a caveat **survives into the label** — off
/// pin, and dirty. A warning printed to stderr is gone when the terminal scrolls; a caveat in
/// the label is in the artifact.
///
/// The label helpers are exercised directly with synthetic pins rather than through `resolve`,
/// because routing them through a real checkout would make each arm depend on whether the
/// developer's tree happens to be dirty at the moment the suite runs.
@Suite("A corpus run derives its tree, target and label instead of taking them from the prompt")
struct CorpusRunPlanTests {

    static let repositoryRoot = URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let pinned = String(repeating: "a", count: 40)
    static let head = String(repeating: "b", count: 40)

    static func entry(localPath: String, measurements: [CorpusManifest.Measurement]) -> CorpusManifest.Entry {
        CorpusManifest.Entry(
            id: "probe",
            subject: "ProbeKit",
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

    static let baseline = CorpusManifest.Measurement(
        apparatus: "prove-then-show",
        kind: "baseline",
        revision: pinned,
        takenOn: "2026-08-14",
        arm: "fixture",
        record: "fixtures/verify-runs/probe.json",
        frozenBecause: nil,
        expectedOutcome: nil,
        answerKey: nil
    )

    /// Write a synthetic manifest into a scratch root and return it.
    static func manifestRoot(_ corpora: [CorpusManifest.Entry]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-plan-\(UUID().uuidString)")
        let file = root.appendingPathComponent(CorpusManifest.relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let manifest = CorpusManifest(
            schemaVersion: CorpusManifest.currentSchemaVersion, corpora: corpora
        )
        try JSONEncoder().encode(manifest).write(to: file)
        return root
    }

    // MARK: - The label carries what a memory would not

    @Test("An off-pin run says so in the label, naming both revisions")
    func offPinLabelNamesBothRevisions() {
        let subject = Self.entry(localPath: "/x", measurements: [Self.baseline])
        let text = CorpusRunPlan.label(
            entry: subject,
            head: Self.head,
            dirty: false,
            pin: .movedOff(head: Self.head, pinned: Self.pinned, dirty: false)
        )
        #expect(text.contains("off pin"))
        #expect(text.contains(String(Self.head.prefix(7))))
        #expect(text.contains(String(Self.pinned.prefix(7))))
    }

    @Test("A dirty run says so in the label")
    func dirtyLabelSaysSo() {
        let subject = Self.entry(localPath: "/x", measurements: [Self.baseline])
        let text = CorpusRunPlan.label(
            entry: subject, head: Self.pinned, dirty: true, pin: .atPin(dirty: true)
        )
        #expect(text.contains("uncommitted changes"))
    }

    @Test("A clean run at its pin carries no caveat and no warning")
    func cleanRunIsUnadorned() {
        let subject = Self.entry(localPath: "/x", measurements: [Self.baseline])
        let text = CorpusRunPlan.label(
            entry: subject, head: Self.pinned, dirty: false, pin: .atPin(dirty: false)
        )
        #expect(text == "ProbeKit ProbeTarget @ \(Self.pinned.prefix(7))")
        #expect(CorpusRunPlan.warnings(entry: subject, pin: .atPin(dirty: false)).isEmpty)
    }

    @Test("A first run on a corpus with no baseline says it is a first run")
    func firstRunSaysSo() {
        let subject = Self.entry(localPath: "/x", measurements: [])
        let text = CorpusRunPlan.label(
            entry: subject, head: Self.head, dirty: false, pin: .noBaseline
        )
        #expect(text.contains("first run"))
    }

    /// The warning has to say what goes wrong, not merely that something did. An off-pin diff
    /// is not invalid — it is *unattributable*, and that is the distinction a reader needs.
    @Test("The off-pin warning names the confound rather than just the mismatch")
    func offPinWarningNamesTheConfound() {
        let subject = Self.entry(localPath: "/x", measurements: [Self.baseline])
        let notes = CorpusRunPlan.warnings(
            entry: subject, pin: .movedOff(head: Self.head, pinned: Self.pinned, dirty: false)
        )
        #expect(notes.count == 1)
        #expect(notes[0].contains("SUBJECT"))
        #expect(notes[0].contains("TOOL"))
    }

    // MARK: - Resolution

    @Test("An unknown id lists what could have been typed instead")
    func unknownIdListsTheKnownOnes() throws {
        let root = try Self.manifestRoot([Self.entry(localPath: "/x", measurements: [Self.baseline])])
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try CorpusRunPlan.resolve(corpusID: "nope", manifestRoot: root)
            Issue.record("expected an unknownCorpus error")
        } catch let error as CorpusRunPlan.ResolveError {
            #expect(error.description.contains("probe"), "the error must list known ids")
        }
    }

    @Test("A corpus with no checkout fails naming the remote to clone")
    func absentCheckoutNamesTheRemote() throws {
        let subject = Self.entry(localPath: "/nonexistent/corpus", measurements: [Self.baseline])
        let root = try Self.manifestRoot([subject])
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try CorpusRunPlan.resolve(corpusID: "probe", manifestRoot: root)
            Issue.record("expected a noCheckout error")
        } catch let error as CorpusRunPlan.ResolveError {
            #expect(error.description.contains("https://example.invalid/probe.git"))
        }
    }

    /// An app has no SwiftPM target and the survey resolves one unconditionally, so the failure
    /// without this is an empty scan reporting *nothing to suggest* — the exact shape
    /// `ProveThenShowSourcesReachTests` records for the layout resolver, where a working
    /// package read as a subject with no laws.
    @Test("An app-shaped corpus is refused, naming the command that can reach it")
    func appShapedCorpusIsRefused() throws {
        let subject = CorpusManifest.Entry(
            id: "probe",
            subject: "ProbeApp",
            kind: "app",
            target: nil,
            sources: ["Shared"],
            remote: "https://example.invalid/probe.git",
            localPath: Self.repositoryRoot.path,
            role: "unfamiliar",
            why: "a fixture",
            measurements: []
        )
        let root = try Self.manifestRoot([subject])
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try CorpusRunPlan.resolve(corpusID: "probe", manifestRoot: root)
            Issue.record("expected a notSurveyable error")
        } catch let error as CorpusRunPlan.ResolveError {
            #expect(error.description.contains("--sources"))
            #expect(error.description.contains("Shared"))
        }
    }

    /// Refused even when the checkout IS present: unreachability is a property of the subject,
    /// not of whether it happens to be cloned, and "no checkout" would send the reader to clone
    /// a repo that still would not survey.
    @Test("The refusal outranks a missing checkout")
    func refusalOutranksAMissingCheckout() throws {
        let subject = CorpusManifest.Entry(
            id: "probe",
            subject: "ProbeApp",
            kind: "app",
            target: nil,
            sources: ["Shared"],
            remote: "https://example.invalid/probe.git",
            localPath: "/nonexistent/corpus",
            role: "unfamiliar",
            why: "a fixture",
            measurements: []
        )
        let root = try Self.manifestRoot([subject])
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try CorpusRunPlan.resolve(corpusID: "probe", manifestRoot: root)
            Issue.record("expected a notSurveyable error")
        } catch let error as CorpusRunPlan.ResolveError {
            #expect(error.description.contains("no SwiftPM target"))
            #expect(!error.description.contains("Clone it from"))
        }
    }

    @Test("The resolved plan takes its tree and target from the manifest")
    func planComesFromTheManifest() throws {
        let subject = Self.entry(localPath: Self.repositoryRoot.path, measurements: [Self.baseline])
        let root = try Self.manifestRoot([subject])
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try CorpusRunPlan.resolve(corpusID: "probe", manifestRoot: root)
        #expect(plan.target == "ProbeTarget")
        #expect(plan.directory.standardizedFileURL == Self.repositoryRoot.standardizedFileURL)
        #expect(plan.label.hasPrefix("ProbeKit ProbeTarget @ "))
    }

    // MARK: - The flags cannot disagree with the manifest

    /// Parsed rather than constructed: an `@Option`'s storage is populated by parsing, and
    /// reading one off a hand-built command traps rather than returning the default.
    static func command(_ arguments: [String]) throws -> SwiftInferCommand.ProveThenShow {
        try SwiftInferCommand.ProveThenShow.parse(arguments)
    }

    @Test("--corpus refuses to sit alongside --target or --directory")
    func corpusIsExclusiveWithTheLooseFlags() throws {
        let withTarget = try Self.command(["--corpus", "probe", "--target", "SomethingElse"])
        #expect(throws: VerifyError.self) { try withTarget.resolveSurvey() }

        let withDirectory = try Self.command(["--corpus", "probe", "--directory", "/somewhere"])
        #expect(throws: VerifyError.self) { try withDirectory.resolveSurvey() }
    }

    @Test("Neither --corpus nor --target is an error that names both")
    func neitherFlagIsAnError() throws {
        do {
            _ = try Self.command([]).resolveSurvey()
            Issue.record("expected invalidArguments")
        } catch let error as VerifyError {
            #expect(error.description.contains("--corpus"))
            #expect(error.description.contains("--target"))
        }
    }

    @Test("The loose-flag path derives no label, leaving the existing default in place")
    func looseFlagsDeriveNoLabel() throws {
        let survey = try Self.command(["--target", "SwiftInferCore"]).resolveSurvey()
        #expect(survey.target == "SwiftInferCore")
        #expect(survey.derivedLabel == nil)
    }
}
