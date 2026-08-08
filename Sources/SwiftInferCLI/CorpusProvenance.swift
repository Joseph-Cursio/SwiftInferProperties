import Foundation

/// Which *version* of a corpus a survey actually ran against.
///
/// Since #172 a corpus that is one of the verifier's own dependencies supersedes
/// the pinned URL declaration — correct, because a survey should test the code in
/// front of you, and silent, which is what #174 is about. `measured-bothPass`
/// already means *"no counterexample in the generated domain"* rather than *"the
/// property holds"*; an unnamed corpus version would make it *"…against a version
/// I will not name"*.
///
/// **Inventing a version is worse than admitting there is none.** A corpus need
/// not be a git checkout, `swift package dump-package` reports no version, and the
/// path alone is not a version because the checkout moves under it. So this
/// resolves a revision when one genuinely exists and *says which case it is*
/// otherwise, rather than degrading to a path and letting the reader assume it
/// pins something.
enum CorpusProvenance {

    /// Human-readable provenance for `root`, suitable for a warning line.
    ///
    /// Three honest answers, and the third is the point: `<path> @ <sha>`,
    /// `<path> @ <sha> (uncommitted changes)`, or `<path> (not a git checkout — no
    /// revision to record)`.
    static func describe(_ root: URL) -> String {
        guard let revision = gitOutput(at: root, ["rev-parse", "--short", "HEAD"]) else {
            return "\(root.path) (not a git checkout — no revision to record)"
        }
        let dirty = gitOutput(at: root, ["status", "--porcelain"]).map { !$0.isEmpty } ?? false
        return "\(root.path) @ \(revision)" + (dirty ? " (uncommitted changes)" : "")
    }

    /// Trimmed stdout of `git -C <root> <arguments>`, or `nil` on any failure.
    ///
    /// Via `DrainedProcess` rather than a bare `Process` — `git status --porcelain`
    /// on a large dirty tree is exactly the output size that deadlocked the
    /// wait-then-read shape in #170.
    private static func gitOutput(at root: URL, _ arguments: [String]) -> String? {
        guard let data = DrainedProcess.standardOutputViaEnv(
            ["git", "-C", root.path] + arguments
        ) else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
