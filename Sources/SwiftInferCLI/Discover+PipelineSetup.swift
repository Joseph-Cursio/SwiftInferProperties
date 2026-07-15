import Foundation
import SwiftInferCore

/// Pipeline-setup resolution for `discover`, split out of `Discover+Pipeline.swift`
/// to keep that file within the length limit. These turn the CLI flags + config +
/// walk-up defaults into a `PipelineSetup`; no behavior change from the move.
extension SwiftInferCommand.Discover {

    static func resolvePipelineSetup(
        directory: URL,
        includePossible: Bool?,
        overrides: ExplicitOverrides,
        diagnostics: any DiagnosticOutput
    ) -> PipelineSetup {
        let configResult = ConfigLoader.load(
            startingFrom: directory,
            explicitPath: overrides.configPath
        )
        for warning in configResult.warnings {
            diagnostics.writeDiagnostic("warning: \(warning)")
        }
        let effectiveIncludePossible =
            includePossible ?? configResult.config.includePossible
        let effectiveVocabularyPath = resolveVocabularyPath(
            cliOverride: overrides.vocabularyPath,
            configValue: configResult.config.vocabularyPath,
            packageRoot: configResult.packageRoot
        )
        let vocabResult = VocabularyLoader.load(
            startingFrom: directory,
            explicitPath: effectiveVocabularyPath
        )
        for warning in vocabResult.warnings {
            diagnostics.writeDiagnostic("warning: \(warning)")
        }
        // TestLifter M6.0 — resolve the test directory separately
        // from the production target. Default walk-up looks for
        // <package-root>/Tests/; the user can override with --test-dir.
        let testDirectory = effectiveTestDirectory(
            productionTarget: directory,
            explicitTestDir: overrides.testDirectory
        ) { diagnostics.writeDiagnostic("warning: \($0)") }
        // V1.32.C — Domain Template Packs (PRD §20.3). Precedence
        // CLI > config > nil (no filter; all templates run).
        let templateFilter = resolveTemplateFilter(
            cliOverride: overrides.packs,
            configValue: configResult.config.packs,
            diagnostics: diagnostics
        )
        return PipelineSetup(
            directory: directory,
            includePossible: effectiveIncludePossible,
            vocabulary: vocabResult.vocabulary,
            testDirectory: testDirectory,
            packageRoot: configResult.packageRoot,
            templateFilter: templateFilter
        )
    }

    /// V1.32.C — resolve the effective template-filter set from the
    /// CLI `--packs` flag, the config `[discover].packs` value, or
    /// `nil` (all templates run). Emits per-name diagnostic warnings
    /// for any unknown pack names and an empty-effective-set warning
    /// so a misconfigured pipeline doesn't silently surface zero
    /// suggestions.
    static func resolveTemplateFilter(
        cliOverride: String?,
        configValue: String?,
        diagnostics: any DiagnosticOutput
    ) -> Set<String>? {
        let effective = cliOverride ?? configValue
        guard let effective else {
            return nil
        }
        for unknown in TemplatePack.unknownPackNames(in: effective) {
            diagnostics.writeDiagnostic(
                "warning: unknown template pack '\(unknown)' (known: "
                    + "numeric, serialization, collections, algebraic, "
                    + "concurrency) — ignoring"
            )
        }
        let packs = TemplatePack.parse(effective)
        let resolved = TemplatePack.resolve(packs)
        if resolved.isEmpty {
            diagnostics.writeDiagnostic(
                "warning: no template packs enabled after parsing '\(effective)'"
                    + " — no suggestions will surface. Did you misspell a pack name?"
            )
        }
        return resolved
    }
}
