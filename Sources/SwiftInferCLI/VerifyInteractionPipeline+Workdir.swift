import Foundation
import SwiftInferCore

/// Cycle 120 — workdir/package-root helpers for the interaction verify
/// pipeline, split out of the main file so the core enum body stays under
/// SwiftLint's `file_length` cap (mirrors the `+Evidence` split).
extension VerifyInteractionPipeline {

    /// Walk up from `directory` looking for `Package.swift`. Same shape as
    /// v1.42 verify's package-root resolution + every other loader in the
    /// project — kept inlined here for the same independent-loader posture.
    static func findPackageRoot(startingFrom directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            let manifest = current.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return current
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current {
                return nil
            }
            current = parent
        }
    }

    /// Filename-safe workdir segment from the candidate's qualified
    /// name (`.` → `_`, so `Inbox.body` → `Inbox_body`). Cycle 120:
    /// a non-nil `identity` (the invariant's normalized 16-char hash)
    /// appends `__<identity>` so sibling identities on one reducer get
    /// distinct workdirs and can build concurrently; `nil` (the bare
    /// `runPipeline` path) preserves the reducer-only segment exactly.
    static func workdirSegment(
        for candidate: ReducerCandidate,
        identity: String? = nil
    ) -> String {
        let base = candidate.qualifiedName.replacingOccurrences(of: ".", with: "_")
        guard let identity, !identity.isEmpty else { return base }
        return "\(base)__\(identity)"
    }
}
