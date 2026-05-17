import Foundation
import SwiftInferCore

/// V1.98 lint pass — side-orchestrator helpers extracted from
/// `DiscoverInteractionCommand.swift`'s struct body so the main
/// file's struct stays under SwiftLint's 250-line `type_body_length`
/// cap after v1.98's `--interactive` branch landed. Contains the
/// `--update-baseline` writer (v1.89), the `--interactive` triage
/// dispatcher (v1.98), and the shared package-root walk-up helper.

/// V1.110 (cycle-103d) — resolved-flag bundle. Replaces the
/// 3-element tuple SwiftLint flags as a `large_tuple` violation.
/// File-scope for the nesting cap; small enough to inline at call
/// sites without ceremony.
public struct DiscoverInteractionEffectiveFlags: Sendable, Equatable {
    public let interactive: Bool
    public let interactiveBridges: Bool
    public let updateBaseline: Bool

    public init(interactive: Bool, interactiveBridges: Bool, updateBaseline: Bool) {
        self.interactive = interactive
        self.interactiveBridges = interactiveBridges
        self.updateBaseline = updateBaseline
    }
}

/// V1.110 (cycle-103d) — bundle of `dispatchSideOrchestrator`
/// dependencies. SwiftLint flagged the original 9-arg form as a
/// `function_parameter_count` violation. The bundle stays
/// file-scope (nesting cap) + lets the dispatch helper stay a
/// 2-arg function (suggestions + inputs).
public struct SideOrchestratorInputs {
    public let effectiveFlags: DiscoverInteractionEffectiveFlags
    public let workingDirectory: URL
    public let target: String
    public let promptInput: any PromptInput
    public let output: any DiscoverOutput
    public let diagnostics: any DiagnosticOutput
    public let dryRun: Bool
    public let firstSeenAt: Date

    public init(
        effectiveFlags: DiscoverInteractionEffectiveFlags,
        workingDirectory: URL,
        target: String,
        promptInput: any PromptInput,
        output: any DiscoverOutput,
        diagnostics: any DiagnosticOutput,
        dryRun: Bool,
        firstSeenAt: Date
    ) {
        self.effectiveFlags = effectiveFlags
        self.workingDirectory = workingDirectory
        self.target = target
        self.promptInput = promptInput
        self.output = output
        self.diagnostics = diagnostics
        self.dryRun = dryRun
        self.firstSeenAt = firstSeenAt
    }
}
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

    /// V1.109 (cycle-103c) — resolve the three-way mutex over
    /// `--interactive` / `--interactive-bridges` /
    /// `--update-baseline`. Precedence (most-specific wins):
    /// `--interactive` > `--interactive-bridges` >
    /// `--update-baseline`. Each downgrade emits a warning to
    /// `diagnostics`. Moved to the side-orchestrators extension in
    /// cycle 103d so the main struct stays under SwiftLint's
    /// body-length cap.
    static func warnAndResolveFlagMutex(
        interactive: Bool,
        interactiveBridges: Bool,
        updateBaseline: Bool,
        diagnostics: any DiagnosticOutput
    ) -> DiscoverInteractionEffectiveFlags {
        var bridges = interactiveBridges
        var baseline = updateBaseline
        if interactive, bridges {
            diagnostics.writeDiagnostic(
                "warning: --interactive and --interactive-bridges are mutually exclusive; "
                    + "--interactive-bridges ignored for this run"
            )
            bridges = false
        }
        let triageActive = interactive || bridges
        if triageActive, baseline {
            diagnostics.writeDiagnostic(
                "warning: --interactive(-bridges) and --update-baseline are mutually exclusive; "
                    + "--update-baseline ignored for this run"
            )
            baseline = false
        }
        return DiscoverInteractionEffectiveFlags(
            interactive: interactive,
            interactiveBridges: bridges,
            updateBaseline: baseline
        )
    }

    /// V1.110 (cycle-103d) — dispatch the resolved triage / baseline
    /// branch based on the effective flags. Extracted from `run` so
    /// the orchestrator stays under SwiftLint's body-length cap.
    /// Pure dispatch — no flag-mutex logic here (that stays in
    /// `warnAndResolveFlagMutex`).
    static func dispatchSideOrchestrator(
        suggestions: [InteractionInvariantSuggestion],
        inputs: SideOrchestratorInputs
    ) throws {
        if inputs.effectiveFlags.interactive {
            try runInteractiveBranch(
                suggestions: suggestions,
                workingDirectory: inputs.workingDirectory,
                target: inputs.target,
                triageIO: InteractionInteractiveTriage.Inputs(
                    prompt: inputs.promptInput,
                    output: inputs.output,
                    diagnostics: inputs.diagnostics,
                    dryRun: inputs.dryRun
                )
            )
        } else if inputs.effectiveFlags.interactiveBridges {
            try runInteractiveBridgesBranch(
                suggestions: suggestions,
                workingDirectory: inputs.workingDirectory,
                target: inputs.target,
                triageIO: InteractionBridgeInteractiveTriage.Inputs(
                    prompt: inputs.promptInput,
                    output: inputs.output,
                    diagnostics: inputs.diagnostics,
                    dryRun: inputs.dryRun
                ),
                firstSeenAt: inputs.firstSeenAt
            )
        } else if inputs.effectiveFlags.updateBaseline {
            try runUpdateBaseline(
                suggestions: suggestions,
                workingDirectory: inputs.workingDirectory,
                target: inputs.target,
                dryRun: inputs.dryRun,
                output: inputs.output
            )
        }
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
