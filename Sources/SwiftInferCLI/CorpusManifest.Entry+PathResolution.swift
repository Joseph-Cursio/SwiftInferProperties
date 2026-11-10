import Foundation

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
