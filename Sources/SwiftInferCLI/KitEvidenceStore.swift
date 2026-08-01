import Foundation
import SwiftInferCore

/// Loads PropertyLawKit results from `.swiftinfer/kit-evidence.json`.
///
/// Same read posture as `VerifyEvidenceStore`: a missing or malformed file yields an empty
/// log rather than throwing, because absence is the normal state — most projects have not
/// exported kit results, and inference's default assumption (that `==` is sound, since the
/// Equatable laws are what would say otherwise) is exactly what an empty log preserves.
///
/// The file is produced by the user's own test run, not by this tool. A suite that already
/// calls `checkHashablePropertyLaws` has `[CheckResult]` in hand; mapping it to this shape
/// is a few lines, and deliberately left to the caller so `SwiftInferCLI` takes no
/// dependency on the kit.
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
    public static func load(
        startingFrom directory: URL,
        explicitPath: String? = nil
    ) -> KitEvidenceLog {
        if let explicitPath {
            return decode(at: URL(fileURLWithPath: explicitPath))
        }
        let root = packageRoot(startingFrom: directory) ?? directory
        return decode(at: root.appendingPathComponent(conventionalRelativePath))
    }

    private static func decode(at url: URL) -> KitEvidenceLog {
        guard let data = try? Data(contentsOf: url),
              let log = try? JSONDecoder().decode(KitEvidenceLog.self, from: data) else {
            return KitEvidenceLog()
        }
        return log
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
