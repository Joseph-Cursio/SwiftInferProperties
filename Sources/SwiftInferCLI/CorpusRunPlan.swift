import Foundation

/// Which tree, which target, and what to call the run — from `--corpus` or from the loose
/// flags.
///
/// `derivedLabel` is nil on the loose-flag path so `--retain-label`'s existing default still
/// applies. A registered corpus derives one, which is the point: a hand-typed label is free
/// text nobody validates, and it is what dates every artifact in `fixtures/verify-runs/`.
///
/// Top-level rather than nested inside the command because `ProveThenShow` is already one
/// level deep in `SwiftInferCommand`, and a third level trips `nesting`.
struct ResolvedSurvey {
    let directory: URL
    let target: String
    let derivedLabel: String?
}

/// Everything `prove-then-show --corpus <id>` needs, resolved out of the manifest instead of
/// typed at the prompt.
///
/// ## What this is actually fixing
///
/// The three facts that make a survey reproducible — which tree, which target, what to call
/// the arm — were all hand-supplied, and the retained runs record what that costs. Each of the
/// four carries a `subjectRevision` pointing into a scratchpad directory that no longer
/// exists, and a `label` typed by hand at the shell. A label is free text no one validates, so
/// "GRDB @ b83108d10 native" is indistinguishable from a label naming the wrong arm.
///
/// Resolving all three from one committed record makes the label a *derived* fact and lets a
/// checkout standing off its pin say so **in the artifact**, rather than in the memory of
/// whoever ran it.
///
/// ## Off-pin warns; it does not refuse
///
/// Surveying a newer commit is how a baseline gets re-based, so refusing would block the
/// normal path. What must not happen is a re-based run being *silently* comparable with the
/// old one: `survey-diff` would then attribute a change in the subject to a change in the
/// tool, which is the single confound the whole retained-run apparatus exists to separate.
struct CorpusRunPlan {

    /// The tree to survey.
    let directory: URL

    let target: String

    /// Derived, never hand-typed, and it carries its own caveats — `(off pin …)` and
    /// `(uncommitted changes)` land in the retained artifact rather than in a memory.
    let label: String

    /// Emitted to stderr before the survey starts. Empty when the checkout is clean and at pin.
    let warnings: [String]

    enum ResolveError: Error, CustomStringConvertible {
        case unknownCorpus(id: String, known: [String])
        case noCheckout(id: String, path: String, remote: String)
        case untracked(id: String, path: String)
        case notSurveyable(id: String, kind: String, sources: String?)

        var description: String {
            switch self {
            case let .notSurveyable(id, kind, sources):
                let location = sources.map { " Its sources are at '\($0)'." } ?? ""
                return "swift-infer prove-then-show: corpus '\(id)' has kind '\(kind)' and "
                    + "declares no SwiftPM target, which this survey resolves "
                    + "unconditionally.\(location) "
                    + "Reach it with `discover-interaction --sources`, the escape hatch built "
                    + "for subjects with no manifest. Refused rather than surveyed, because "
                    + "resolving a target that does not exist scans an empty directory and "
                    + "reports *nothing to suggest* — indistinguishable from a clean result."

            case let .unknownCorpus(id, known):
                return "swift-infer prove-then-show: no corpus '\(id)' in "
                    + "\(CorpusManifest.relativePath). Known: \(known.joined(separator: ", ")). "
                    + "Add an entry there rather than passing --target and --directory by hand "
                    + "— an unregistered survey is one nobody can reproduce."

            case let .noCheckout(id, path, remote):
                return "swift-infer prove-then-show: corpus '\(id)' has no checkout at "
                    + "'\(path)'. Clone it from \(remote), or correct `localPath` in "
                    + "\(CorpusManifest.relativePath) if it lives elsewhere on this machine."

            case let .untracked(id, path):
                return "swift-infer prove-then-show: '\(path)' (corpus '\(id)') is not a git "
                    + "checkout, so there is no revision to record and none can be invented. A "
                    + "survey taken here could not be dated, which is the failure the corpus "
                    + "manifest exists to prevent."
            }
        }
    }

    /// Resolve `id` against the manifest at `manifestRoot`.
    static func resolve(corpusID: String, manifestRoot: URL) throws -> Self {
        let manifest = try CorpusManifest.load(repositoryRoot: manifestRoot)
        guard let entry = manifest.entry(id: corpusID) else {
            throw ResolveError.unknownCorpus(id: corpusID, known: manifest.identifiers)
        }
        // Checked before the checkout, deliberately: an app-shaped subject is unreachable by
        // this command whether or not it happens to be cloned, and "no checkout" would send
        // the reader to clone a repo that still would not survey.
        guard let target = entry.target, entry.isSurveyable else {
            throw ResolveError.notSurveyable(
                id: entry.id, kind: entry.kind, sources: entry.sources
            )
        }
        let status = CorpusStatus.resolve(entry, repositoryRoot: manifestRoot)
        switch status.checkout {
        case let .missing(path):
            throw ResolveError.noCheckout(id: entry.id, path: path, remote: entry.remote)

        case let .untracked(path):
            throw ResolveError.untracked(id: entry.id, path: path)

        case let .resolved(path, head, dirty):
            return Self(
                directory: URL(fileURLWithPath: path),
                target: target,
                label: label(entry: entry, head: head, dirty: dirty, pin: status.pin),
                warnings: warnings(entry: entry, pin: status.pin)
            )
        }
    }

    /// Internal rather than private so the caveats can be asserted against synthetic pins.
    /// Testing them through `resolve` would make the arms depend on whether the developer's
    /// working tree happens to be dirty today, which is the opposite of a fixture.
    static func label(
        entry: CorpusManifest.Entry, head: String, dirty: Bool, pin: CorpusPin
    ) -> String {
        var text = "\(entry.subject) \(entry.reachLabel) @ \(head.prefix(7))"
        if case let .movedOff(_, pinned, _) = pin {
            text += " (off pin — baseline taken at \(pinned.prefix(7)))"
        }
        if case .noBaseline = pin {
            text += " (first run — no prior baseline)"
        }
        if dirty { text += " (uncommitted changes)" }
        return text
    }

    static func warnings(entry: CorpusManifest.Entry, pin: CorpusPin) -> [String] {
        var notes: [String] = []
        if case let .movedOff(head, pinned, _) = pin {
            notes.append(
                "corpus '\(entry.id)' is at \(head.prefix(7)) but its baseline was measured at "
                    + "\(pinned.prefix(7)). This run is still worth taking — that is how a "
                    + "baseline gets re-based — but a diff against the retained run will mix a "
                    + "change in the SUBJECT with a change in the TOOL, and cannot tell you "
                    + "which moved. Check out the pin for a tool-only comparison."
            )
        }
        if case .atPin(true) = pin {
            notes.append(
                "corpus '\(entry.id)' is at its pin but the tree is DIRTY, so this run measures "
                    + "uncommitted work that no revision names. The label records it; the "
                    + "changes themselves are unrecoverable once the tree is cleaned."
            )
        }
        if case .movedOff(_, _, true) = pin {
            notes.append("corpus '\(entry.id)' is also DIRTY on top of being off pin.")
        }
        return notes
    }
}
