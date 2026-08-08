import Foundation
import SwiftInferCore

/// Run-side helpers for `swift-infer discover` — the bits the CLI
/// orchestrator calls after `collectVisibleSuggestions` returns.
/// Split out of `Discover+Pipeline.swift` to keep both files under
/// SwiftLint's file_length cap. The pure pipeline-collection code
/// stays in `Discover+Pipeline.swift`; the `--update-baseline` write,
/// the `--interactive` triage driver, and the per-flag path-resolution
/// helpers live here.
extension SwiftInferCommand.Discover {

    /// Snapshot the current run's surface-suggestion identities to
    /// `.swiftinfer/baseline.json` (M6.5). Honors `--dry-run` by
    /// reporting the would-be path on stdout and skipping the write.
    /// The renderer still emits the normal suggestion stream after
    /// the snapshot — `--update-baseline` is additive, not a mode
    /// swap.
    static func runUpdateBaseline(
        suggestions: [Suggestion],
        packageRoot: URL,
        dryRun: Bool,
        output: any DiscoverOutput
    ) throws {
        let baseline = Baseline(
            entries: suggestions.map { suggestion in
                BaselineEntry(
                    identityHash: suggestion.identity.normalized,
                    template: suggestion.templateName,
                    scoreAtSnapshot: suggestion.score.total,
                    tier: suggestion.score.tier
                )
            }
        )
        let path = BaselineLoader.defaultPath(for: packageRoot)
        if dryRun {
            output.write("[dry-run] would write baseline to \(path.path)")
            return
        }
        try BaselineLoader.write(baseline, to: path)
        output.write("Wrote baseline to \(path.path) (\(suggestions.count) entries).")
    }

    /// Drive the M6.4 `--interactive` triage session: load the
    /// existing decisions, walk surviving suggestions through the
    /// `[A/s/n/?]` prompt loop, persist the updated decisions
    /// (unless `--dry-run`).
    static func runInteractive(
        suggestions: [Suggestion],
        packageRoot: URL,
        context: InteractiveTriage.Context
    ) throws {
        let decisionsResult = DecisionsLoader.load(startingFrom: packageRoot)
        for warning in decisionsResult.warnings {
            context.diagnostics.writeDiagnostic("warning: \(warning)")
        }
        let outcome = try InteractiveTriage.run(
            suggestions: suggestions,
            existingDecisions: decisionsResult.decisions,
            context: context
        )
        if !context.dryRun, outcome.updatedDecisions != decisionsResult.decisions {
            let path = decisionsResult.packageRoot.map(DecisionsLoader.defaultPath(for:))
                ?? DecisionsLoader.defaultPath(for: packageRoot)
            try DecisionsLoader.write(outcome.updatedDecisions, to: path)
        }
    }

    /// Resolve the vocabulary path with CLI > config > implicit-walk-up
    /// precedence. Relative paths in config are resolved against the
    /// package root the config loader walked up to; absolute paths
    /// pass through unchanged. Absoluteness is checked on the raw
    /// string — `URL(fileURLWithPath:)` would otherwise re-anchor a
    /// relative path against the current working directory before we
    /// got the chance to join it with the package root.
    static func resolveVocabularyPath(
        cliOverride: URL?,
        configValue: String?,
        packageRoot: URL?
    ) -> URL? {
        if let cliOverride {
            return cliOverride
        }
        guard let raw = configValue else {
            return nil
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        if let packageRoot {
            return packageRoot.appendingPathComponent(raw)
        }
        return URL(fileURLWithPath: raw)
    }

    /// TestLifter M6.0 — resolve TestLifter's scan directory with
    /// precedence: explicit `--test-dir` (warn + fall through if path
    /// doesn't exist) > walk-up to `<package-root>/Tests/` > the
    /// production target itself (degraded fallback for tmpdir fixtures
    /// without `Package.swift`). Pure function over its inputs.
    public static func effectiveTestDirectory(
        productionTarget: URL,
        explicitTestDir: URL?,
        diagnostic: (String) -> Void
    ) -> URL {
        let fileManager = FileManager.default
        if let explicit = explicitTestDir {
            if fileManager.fileExists(atPath: explicit.path) {
                return explicit
            }
            diagnostic(
                "--test-dir path '\(explicit.path)' does not exist; "
                    + "falling back to walk-up resolution"
            )
        }
        if let packageRoot = findPackageRootForTestDir(startingFrom: productionTarget) {
            let tests = packageRoot.appendingPathComponent("Tests")
            if fileManager.fileExists(atPath: tests.path) {
                return tests
            }
        }
        return productionTarget
    }

    /// The scan roots TestLifter should read, scoped to the test targets that could
    /// be exercising `productionTarget`.
    ///
    /// The plural form of `effectiveTestDirectory`, and the fix for the
    /// **target-scoping defect**: production code resolved to `Sources/<target>/`
    /// while lifting read `<package-root>/Tests/` wholesale, so every lifted law was
    /// attributed to whichever target you happened to name. Measured on this repo,
    /// Strong-tier rows went **26 → 7** once scoped, with `SwiftInferKitEvidence`
    /// and `SwiftInferMacroImpl` at **4 of 4** rows about other targets' code
    /// (`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §1).
    ///
    /// Precedence, deliberately identical to the singular form at every step where
    /// the singular form had an answer:
    ///   1. explicit `--test-dir` — the user override always wins, unscoped, and
    ///      still warns-and-falls-through when the path does not exist;
    ///   2. **manifest-scoped test targets** (the new step) — see `TestTargetScope`;
    ///   3. walk-up to `<package-root>/Tests/` — the pre-fix behaviour, reached
    ///      whenever the manifest cannot answer;
    ///   4. the production target itself — degraded fallback for tmpdir fixtures
    ///      without a `Package.swift`.
    ///
    /// **Step 2 may legitimately return an empty array**, and that is the point: a
    /// target no test target reaches lifts nothing. `TestTargetScope` distinguishes
    /// that from "cannot answer" (`nil`), which falls through to step 3 — collapsing
    /// the two would either reintroduce the defect or silently disable lifting.
    static func effectiveTestDirectories(
        productionTarget: URL,
        explicitTestDir: URL?,
        diagnostic: (String) -> Void
    ) -> [URL] {
        let fileManager = FileManager.default
        if let explicit = explicitTestDir {
            if fileManager.fileExists(atPath: explicit.path) {
                return [explicit]
            }
            diagnostic(
                "--test-dir path '\(explicit.path)' does not exist; "
                    + "falling back to walk-up resolution"
            )
        }
        if let packageRoot = findPackageRootForTestDir(startingFrom: productionTarget) {
            // The module name follows the `Sources/<target>/` convention `--target`
            // resolves through. A directory that is not a declared target — the
            // `--sources` escape hatch, or a manifest `path` override — makes
            // `TestTargetScope` answer `nil`, not empty, so this cannot silently
            // switch lifting off.
            let module = productionTarget.standardizedFileURL.lastPathComponent
            if let scoped = TestTargetScope.testDirectories(
                exercising: module,
                packageRoot: packageRoot
            ) {
                return scoped
            }
            let tests = packageRoot.appendingPathComponent("Tests")
            if fileManager.fileExists(atPath: tests.path) {
                return [tests]
            }
        }
        return [productionTarget]
    }
}
