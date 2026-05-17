import Foundation
import SwiftInferCore

/// V1.98 lint pass — side-orchestrator helpers extracted from
/// `DiscoverInteractionCommand.swift`'s struct body so the main
/// file's struct stays under SwiftLint's 250-line `type_body_length`
/// cap after v1.98's `--interactive` branch landed. Contains the
/// `--update-baseline` writer (v1.89), the `--interactive` triage
/// dispatcher (v1.98), and the shared package-root walk-up helper.
extension SwiftInferCommand.DiscoverInteraction {

    /// V1.98 — extracted from `run` so the orchestrator stays under
    /// SwiftLint's body-length cap. Resolves the package root by
    /// walking up from `Sources/<target>/`, then hands the suggestion
    /// list to `InteractionInteractiveTriage.run`.
    static func runInteractiveBranch(
        suggestions: [InteractionInvariantSuggestion],
        workingDirectory: URL,
        target: String,
        triageIO: InteractionInteractiveTriage.Inputs
    ) throws {
        let sourcesDirectory = workingDirectory
            .appendingPathComponent("Sources")
            .appendingPathComponent(target)
        let packageRoot = findPackageRoot(startingFrom: sourcesDirectory)
            ?? workingDirectory
        _ = try InteractionInteractiveTriage.run(
            suggestions: suggestions,
            packageRoot: packageRoot,
            inputs: triageIO
        )
    }

    /// V1.109 (cycle-103c) — bridge-level analog of
    /// `runInteractiveBranch`. Groups Strong-tier suggestions into
    /// bridges via `InteractionInvariantBridge.bridges(from:now:)`,
    /// then hands them to `InteractionBridgeInteractiveTriage.run`.
    /// Emits a sentinel + early-returns when the bridge list is
    /// empty (the common case until calibration promotes a family
    /// to Strong tier).
    static func runInteractiveBridgesBranch(
        suggestions: [InteractionInvariantSuggestion],
        workingDirectory: URL,
        target: String,
        triageIO: InteractionBridgeInteractiveTriage.Inputs,
        firstSeenAt: Date
    ) throws {
        let bridges = InteractionInvariantBridge.bridges(
            from: suggestions,
            now: firstSeenAt
        )
        if bridges.isEmpty {
            triageIO.output.write(
                "No bridges fire — all suggestions are below Strong tier or fewer than "
                    + "the 3-witness threshold per reducer. Bridges fire only on Strong-tier "
                    + "suggestions (PRD §3.5 — gated on the calibration loop's tier-promotion "
                    + "rule). Re-run after calibration promotes a family to Strong / Verified."
            )
            return
        }
        let sourcesDirectory = workingDirectory
            .appendingPathComponent("Sources")
            .appendingPathComponent(target)
        let packageRoot = findPackageRoot(startingFrom: sourcesDirectory)
            ?? workingDirectory
        _ = try InteractionBridgeInteractiveTriage.run(
            bridges: bridges,
            packageRoot: packageRoot,
            inputs: triageIO
        )
    }

    /// V1.89 — snapshot the current run's Strong-tier-or-Verified
    /// suggestions to `.swiftinfer/interaction-baseline.json`.
    /// Symmetric write side for M10's drift read. Honors `--dry-run`
    /// by reporting the would-be path on stdout and skipping the
    /// write.
    ///
    /// **Filter.** Strong + Verified only, matching
    /// `InteractionDriftDetector.warnings` and
    /// `InteractionInvariantBridge`. Persisting Possible / Likely
    /// would write entries that drift would never warn against —
    /// the two surfaces would silently desync. Today (pre-
    /// calibration) every M4–M7 family ships at default `.possible`
    /// so the snapshot is typically empty; that's correct (drift
    /// today warns on nothing, and the snapshot records that
    /// state).
    static func runUpdateBaseline(
        suggestions: [InteractionInvariantSuggestion],
        workingDirectory: URL,
        target: String,
        dryRun: Bool,
        output: any DiscoverOutput
    ) throws {
        let entries = suggestions
            .filter { $0.tier == .strong || $0.tier == .verified }
            .map { suggestion in
                InteractionBaselineEntry(
                    identityHash: suggestion.identity.normalized,
                    family: suggestion.family,
                    scoreAtSnapshot: suggestion.score,
                    tier: suggestion.tier,
                    reducerQualifiedName: suggestion.reducerQualifiedName
                )
            }
        let baseline = InteractionBaseline(entries: entries)
        let sourcesDirectory = workingDirectory
            .appendingPathComponent("Sources")
            .appendingPathComponent(target)
        let packageRoot = findPackageRoot(startingFrom: sourcesDirectory)
            ?? workingDirectory
        let path = InteractionBaselineLoader.defaultPath(for: packageRoot)
        if dryRun {
            output.write(
                "[dry-run] would write interaction-baseline to "
                    + "\(path.path) (\(entries.count) entries)."
            )
            return
        }
        try InteractionBaselineLoader.write(baseline, to: path)
        output.write(
            "Wrote interaction-baseline to \(path.path) (\(entries.count) entries)."
        )
    }

    /// Walk up from `directory` looking for `Package.swift`. Same
    /// shape as `InteractionBaselineLoader.findPackageRoot` (kept
    /// private there); inlined here to keep the side-orchestrator
    /// helpers self-contained without widening the loader's API.
    /// Internal access (vs private) so both
    /// `runUpdateBaseline` and `runInteractiveBranch` reach it from
    /// the same extension file.
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
}
