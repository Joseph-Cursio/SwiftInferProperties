import Foundation

/// Loads PropertyLawKit results from `.swiftinfer/kit-evidence.json`.
///
/// Same read posture as `VerifyEvidenceStore`: a missing or malformed file yields an empty
/// log rather than throwing, because absence is the normal state — most projects have not
/// exported kit results, and inference's default assumption (that `==` is sound, since the
/// Equatable laws are what would say otherwise) is exactly what an empty log preserves.
///
/// ## Who writes it
///
/// The user's own test run, via `SwiftInferKitEvidence`'s `KitEvidenceRecorder` — a leaf
/// library that depends on `PropertyLawKit` so this target does not have to.
///
/// **That recorder did not exist until 2026-08-02, and its absence made this whole feature
/// unreachable.** `load` shipped wired into `discover`, `write` shipped with *zero callers*
/// in Sources or Tests, no subcommand exported anything, and the kit has never heard of this
/// format — so the file could only appear if a user hand-authored JSON matching
/// `KitEvidenceLog`'s `Codable` shape, which nothing documented. Meanwhile the diagnostic
/// told them to "export results", an action with no supported path. Half a feedback loop,
/// described in its own commit message as closing one.
public enum KitEvidenceStore {

    public static let conventionalRelativePath = ".swiftinfer/kit-evidence.json"

    /// - Parameter directory: where to start looking. `.swiftinfer/` lives at the PACKAGE
    ///   ROOT, not beside the sources, so this walks up looking for `Package.swift` — the
    ///   same resolution `VerifyEvidenceStore.load(startingFrom:)` performs.
    ///
    ///   Passing the scan directory here without walking up was the first version's bug: a
    ///   `--sources App/Sources` run looked for `App/Sources/.swiftinfer/kit-evidence.json`,
    ///   found nothing, and silently proceeded as though the kit had never run — which is
    ///   indistinguishable from the honest "no evidence" case and would have made this whole
    ///   feature a no-op wherever `--sources` is used.
    /// - Parameter diagnostic: reports a log that EXISTS but cannot be read. Defaults to a
    ///   no-op so existing callers are unchanged, matching `SeedRestrictionResolver.resolve`.
    public static func load(
        startingFrom directory: URL,
        explicitPath: String? = nil,
        diagnostic: (String) -> Void = { _ in /* no-op */ }
    ) -> KitEvidenceLog {
        if let explicitPath {
            return decode(at: URL(fileURLWithPath: explicitPath), diagnostic: diagnostic)
        }
        let root = packageRoot(startingFrom: directory) ?? directory
        return decode(
            at: root.appendingPathComponent(conventionalRelativePath),
            diagnostic: diagnostic
        )
    }

    /// **An absent log and an unreadable one are different facts, and only one is normal.**
    ///
    /// Absent is the common case and not an error: most projects never record kit evidence.
    /// Unreadable — the file is there and will not parse — means evidence exists and cannot
    /// be counted, which is the case `ProtocolCoverageAudit` cannot survive being told wrong.
    /// Its three states are `verified` / `assumed` / `contradicted`, and its own doc says
    /// `wasExercised` cannot separate the last two because **"the log's EMPTINESS is what
    /// tells them apart"**. A corrupt log therefore reads as `assumed` — *normal, one
    /// aggregate line* — when the truth may be `contradicted`: the project demonstrably uses
    /// the kit and demonstrably did not run it here, so those laws are checked by nothing.
    ///
    /// The bug this closes is the one the `load` doc above already describes for a different
    /// cause. That instance was fixed by walking up to the package root; this one was left
    /// swallowing, and it fails in exactly the direction that doc warns about.
    private static func decode(
        at url: URL,
        diagnostic: (String) -> Void = { _ in /* no-op */ }
    ) -> KitEvidenceLog {
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Genuinely absent. The normal state, and deliberately silent — saying
            // something here would put a line on every run of every project that has
            // never recorded evidence.
            return KitEvidenceLog()
        }
        do {
            return try JSONDecoder().decode(KitEvidenceLog.self, from: Data(contentsOf: url))
        } catch {
            diagnostic(
                "warning: kit evidence exists at \(url.path) but could not be read — "
                    + "\(error). It is being treated as NO evidence, which reads as "
                    + "\"the kit was never run here\" when it may mean the opposite. "
                    + "Coverage claims derived from it are unreliable until this is fixed."
            )
            return KitEvidenceLog()
        }
    }

    /// Nearest ancestor holding a `Package.swift`, or the first holding a `.swiftinfer/` —
    /// the second clause so an Xcode project, which has no manifest, is still reachable.
    static func packageRoot(startingFrom directory: URL) -> URL? {
        var candidate = directory.standardizedFileURL
        while true {
            let manifest = candidate.appendingPathComponent("Package.swift")
            let store = candidate.appendingPathComponent(".swiftinfer")
            if FileManager.default.fileExists(atPath: manifest.path)
                || FileManager.default.fileExists(atPath: store.path) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            if parent == candidate { return nil }
            candidate = parent
        }
    }

    public static func write(_ log: KitEvidenceLog, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(log).write(to: url, options: .atomic)
    }
}
