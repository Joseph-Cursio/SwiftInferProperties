import Foundation

/// What is actually on disk for a corpus entry, and whether it matches the pin its baseline
/// was measured against.
///
/// ## Cannot-answer is a state, not a pass
///
/// The corpus lives outside this repository, and this project is worked from two machines, so
/// a clone that is present on one and absent on the other is the ordinary case. The tempting
/// shape — available *and* at pin, everything else off — would make a missing clone read as a
/// clean bill of health, which is exactly the failure `DeferralFalsifierTests` reports as
/// `unavailable` rather than folding into "absent".
///
/// So there are three answers and the third is the point: at pin, off pin, or **could not
/// check**. The renderer states the denominator on every run for the same reason — a summary
/// that says "all corpora at pin" while having checked one of three is a confident zero.
enum CorpusCheckout: Equatable, Sendable {

    /// Nothing at the resolved path.
    case missing(path: String)

    /// Something is there, but it is not a git checkout — so there is no revision to compare
    /// and none can be invented. `CorpusProvenance`'s standing rule.
    case untracked(path: String)

    case resolved(path: String, head: String, dirty: Bool)

    /// Read the checkout for an entry. Touches only the local filesystem and `git`; never the
    /// network, so a stale clone reports as off-pin rather than being silently fetched.
    static func read(_ entry: CorpusManifest.Entry, repositoryRoot: URL) -> Self {
        let url = entry.resolvedPath(repositoryRoot: repositoryRoot)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else { return .missing(path: url.path) }
        guard let head = CorpusProvenance.head(at: url) else { return .untracked(path: url.path) }
        return .resolved(path: url.path, head: head.revision, dirty: head.dirty)
    }

    var path: String {
        switch self {
        case let .missing(path), let .untracked(path), let .resolved(path, _, _):
            return path
        }
    }
}

/// Whether a corpus checkout stands where its baseline was measured.
enum CorpusPin: Equatable, Sendable {

    /// The entry lists no baseline, so there is no pin to stand off. Enqueued, never swept.
    case noBaseline

    /// The checkout could not be read. Never merged into either of the two below.
    case uncheckable

    /// `dirty` is carried rather than promoted to its own case because it is orthogonal:
    /// a dirty tree at the pin and a dirty tree off it are different problems.
    case atPin(dirty: Bool)

    case movedOff(head: String, pinned: String, dirty: Bool)

    /// The entry HAS a baseline, and that baseline records no revision — so there is nothing to
    /// stand at or off, and never will be.
    ///
    /// **Deliberately not folded into `noBaseline` or `movedOff`.** `noBaseline` says *enqueued,
    /// never swept*, which invites a sweep; `movedOff` says *check out the pin*, which invites a
    /// fetch. Both are actionable and both would be wrong here — the measurement happened and its
    /// subject revision is gone, so the only honest instruction is *re-run it and record the
    /// revision this time*. This is the same argument `uncheckable` already makes against being
    /// merged into the other two.
    case revisionUnrecoverable

    /// **The checkout is read first, and the order is a decision.** For a corpus that is
    /// neither cloned nor swept both answers are true, and `noBaseline` is the misleading one:
    /// *nothing to compare a run here against* implies the tree is present and merely unswept,
    /// when in fact there is no tree. `uncheckable` says the thing the reader has to act on.
    static func verdict(entry: CorpusManifest.Entry, checkout: CorpusCheckout) -> Self {
        guard case let .resolved(_, head, dirty) = checkout else { return .uncheckable }
        guard let baseline = entry.baselineMeasurement else { return .noBaseline }
        guard let pinned = baseline.revision else { return .revisionUnrecoverable }
        return head == pinned
            ? .atPin(dirty: dirty)
            : .movedOff(head: head, pinned: pinned, dirty: dirty)
    }

    /// A stable one-word token for the verdict, for artifacts rather than for readers.
    ///
    /// **Separate from the rendered sentence on purpose.** `CorpusStatusRenderer.describe`
    /// writes prose that is meant to be re-worded whenever it explains the state badly — it has
    /// been, twice. A recorded run must survive that: a census from last month has to stay
    /// comparable with one from today, and it would not if its stored verdict were whatever
    /// sentence the renderer happened to use. Tokens are the contract; sentences are the copy.
    var token: String {
        switch self {
        case .noBaseline: return "no-baseline"
        case .uncheckable: return "uncheckable"
        case .revisionUnrecoverable: return "revision-unrecoverable"
        case let .atPin(dirty): return dirty ? "at-pin-dirty" : "at-pin"
        case let .movedOff(_, _, dirty): return dirty ? "moved-off-dirty" : "moved-off"
        }
    }

    /// True when a survey taken here would be comparable against the retained baseline.
    ///
    /// `noBaseline` is **not** comparable — there is nothing to compare with — and saying so
    /// keeps "nothing to check" out of the pass column.
    var isComparable: Bool {
        if case .atPin(let dirty) = self { return !dirty }
        return false
    }
}

/// One entry, resolved.
struct CorpusStatus: Sendable {
    let entry: CorpusManifest.Entry
    let checkout: CorpusCheckout
    let pin: CorpusPin

    static func resolve(_ entry: CorpusManifest.Entry, repositoryRoot: URL) -> Self {
        let checkout = CorpusCheckout.read(entry, repositoryRoot: repositoryRoot)
        return Self(
            entry: entry,
            checkout: checkout,
            pin: CorpusPin.verdict(entry: entry, checkout: checkout)
        )
    }

    static func resolveAll(_ manifest: CorpusManifest, repositoryRoot: URL) -> [Self] {
        manifest.corpora.map { resolve($0, repositoryRoot: repositoryRoot) }
    }
}
