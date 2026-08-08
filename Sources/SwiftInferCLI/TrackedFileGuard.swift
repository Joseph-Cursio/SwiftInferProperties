import Foundation

/// Say when a write landed on a file git is tracking.
///
/// `verify --all-from-index` persists to `.swiftinfer/verify-evidence.json`, which is the
/// right place for it and gitignored in this repo's own root. It is **not** gitignored
/// everywhere: `fixtures/cycle27-surface/.swiftinfer/verify-evidence.json` is committed
/// deliberately as that corpus's frozen answer key, and a user who commits their own
/// evidence — a reasonable thing to do, since `docc` reads it to decide what is
/// verified — is in the same position.
///
/// **The failure this exists to stop is not lost data; it is a comparison against
/// itself.** #129: re-verifying the fixture and diffing against the frozen evidence
/// reported *0 drift*, which was false — the run had already rewritten the file, so the
/// diff compared the run against its own output. The tell was arithmetic, not suspicion:
/// frozen was 39/8/6 and the rerun printed 35/8/5 plus 5 errors, and "0 drifted" cannot
/// be true alongside different distributions.
///
/// It bit a second time on 2026-08-08 while closing #130 on that same fixture, and was
/// avoided only by reading the baseline through `git show HEAD:…` because #129 was
/// already known. A warning is the difference between knowing and remembering.
enum TrackedFileGuard {

    /// A warning line if `path` is tracked by git, otherwise `nil`.
    ///
    /// Best-effort and silent on every uncertainty: no git, not a repository, git
    /// unavailable, or any non-zero exit all yield `nil`. A guard that guessed would
    /// print a warning about an untracked file, and a false alarm on every run is how a
    /// warning stops being read.
    static func overwriteWarning(for path: URL) -> String? {
        guard isTracked(path) else { return nil }
        return "\(path.path) is tracked by git and this run just rewrote it. If you were "
            + "comparing against it as a baseline, that baseline is now this run's own "
            + "output — recover it with `git show HEAD:\(gitRelativePath(path) ?? path.path)`. "
            + "Use --no-persist-evidence to measure without touching it."
    }

    /// `git ls-files --error-unmatch <path>` exits 0 only for a tracked path.
    ///
    /// Deliberately not `git status`: a tracked file that is *unmodified* still needs the
    /// warning, because the point is that this run is about to modify it.
    private static func isTracked(_ path: URL) -> Bool {
        let directory = path.deletingLastPathComponent()
        return DrainedProcess.standardOutputViaEnv(
            ["git", "-C", directory.path, "ls-files", "--error-unmatch", path.lastPathComponent]
        ) != nil
    }

    /// The path as `git show HEAD:…` wants it — relative to the repository root.
    /// `nil` when it cannot be resolved, in which case the caller falls back to the
    /// absolute path, which is wrong for `git show` but still identifies the file.
    private static func gitRelativePath(_ path: URL) -> String? {
        let directory = path.deletingLastPathComponent()
        guard let data = DrainedProcess.standardOutputViaEnv(
            ["git", "-C", directory.path, "rev-parse", "--show-toplevel"]
        ), let root = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty else { return nil }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.path.hasPrefix(prefix) else { return nil }
        return String(path.path.dropFirst(prefix.count))
    }
}
