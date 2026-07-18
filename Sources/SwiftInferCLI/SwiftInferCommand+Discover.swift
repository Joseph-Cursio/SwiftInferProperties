import ArgumentParser
import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// `Discover`'s behavior — split out of `SwiftInferCommand.swift` to keep that
/// file within the `file_length` limit and the `Discover` struct's primary
/// declaration within the `type_body_length` limit. Property wrappers
/// (`@Option`/`@Flag`) are stored properties and must stay in the primary
/// struct declaration; everything else — directory resolution, the
/// `ArgumentParser` entry point, and the pure pipeline — moves here.
extension SwiftInferCommand.Discover {

    /// Resolves the directory to scan from exactly one of `--target` / `--sources`.
    ///
    /// `--target` keeps the SwiftPM `Sources/<target>/` convention; `--sources` scans a directory
    /// as given (the Xcode escape hatch, C1). Passing both is ambiguous and passing neither leaves
    /// nothing to scan — both are loud errors rather than a silent default, the same
    /// no-confident-zero discipline the rest of this command holds to.
    public static func resolveScanDirectory(target: String?, sources: String?) throws -> URL {
        switch (target, sources) {
        case let (targetName?, nil):
            return try TargetDirectory.resolve(targetName)

        case let (nil, sourcesPath?):
            return try TargetDirectory.resolveSources(sourcesPath)

        case (nil, nil):
            throw ValidationError(
                "pass exactly one of --target <SwiftPM target> or --sources <directory>. For an "
                    + "Xcode project — which has no `Sources/<target>/` layout — use --sources and "
                    + "point it at the folder your `.swift` files live in."
            )

        case (.some, .some):
            throw ValidationError(
                "--target and --sources are mutually exclusive: --target applies the "
                    + "`Sources/<target>/` convention, --sources scans a directory as given. Pass "
                    + "one."
            )
        }
    }

    public func run() async throws {
        let directory = try Self.resolveScanDirectory(target: target, sources: sources)
        let explicitVocabularyPath = vocabulary.map { URL(fileURLWithPath: $0) }
        let explicitConfigPath = config.map { URL(fileURLWithPath: $0) }
        let explicitTestDirPath = testDir.map { URL(fileURLWithPath: $0) }
        let seedManifest = try seeds.map { try Self.loadSeedManifest(at: URL(fileURLWithPath: $0)) }
        try Self.run(
            directory: directory,
            includePossible: includePossible,
            explicitVocabularyPath: explicitVocabularyPath,
            explicitConfigPath: explicitConfigPath,
            explicitTestDirectory: explicitTestDirPath,
            packsOverride: packs,
            statsOnly: statsOnly,
            effectAnnotations: effectAnnotations,
            docstringAdvice: docstringAdvice,
            dryRun: dryRun,
            interactive: interactive,
            updateBaseline: updateBaseline,
            seedManifest: seedManifest,
            output: PrintOutput(),
            diagnostics: PrintDiagnosticOutput()
        )
    }

    /// Pure pipeline — exposed at the type level so tests exercise
    /// discovery without going through ArgumentParser or stdout.
    ///
    /// Precedence per the M2 plan: CLI > config > defaults. A `nil`
    /// `includePossible` means "no CLI flag passed; let config (or
    /// the default) decide". A non-nil value wins over both. Same
    /// shape for `explicitVocabularyPath`: when nil, the CLI looks
    /// at `[discover].vocabularyPath` in config; when also unset
    /// there, falls back to the conventional walk-up location.
    public static func run(
        directory: URL,
        includePossible: Bool? = nil,
        explicitVocabularyPath: URL? = nil,
        explicitConfigPath: URL? = nil,
        explicitTestDirectory: URL? = nil,
        packsOverride: String? = nil,
        statsOnly: Bool = false,
        effectAnnotations: Bool = false,
        docstringAdvice: Bool = false,
        dryRun: Bool = false,
        interactive: Bool = false,
        updateBaseline: Bool = false,
        seedManifest: SeedManifest? = nil,
        promptInput: any PromptInput = StdinPromptInput(),
        output: any DiscoverOutput,
        diagnostics: any DiagnosticOutput = PrintDiagnosticOutput()
    ) throws {
        let evidenceByIdentity = loadVerifyEvidenceMap(directory: directory, diagnostics: diagnostics)
        let pipeline = try collectVisibleSuggestions(
            directory: directory,
            includePossible: includePossible,
            explicitVocabularyPath: explicitVocabularyPath,
            explicitConfigPath: explicitConfigPath,
            explicitTestDirectory: explicitTestDirectory,
            packsOverride: packsOverride,
            verifyEvidenceByIdentity: evidenceByIdentity,
            diagnostics: diagnostics
        )
        let visible = focus(pipeline, with: seedManifest, diagnostics: diagnostics)

        warnIfConflictingModes(
            interactive: interactive, updateBaseline: updateBaseline, diagnostics: diagnostics
        )
        if interactive {
            try runInteractiveBranch(
                visible: visible,
                pipeline: pipeline,
                directory: directory,
                triageIO: DiscoverInteractiveIO(
                    prompt: promptInput,
                    output: output,
                    diagnostics: diagnostics,
                    dryRun: dryRun
                ),
                evidenceByIdentity: evidenceByIdentity
            )
            return
        }
        if updateBaseline {
            try runUpdateBaseline(
                suggestions: visible,
                packageRoot: pipeline.packageRoot ?? directory,
                dryRun: dryRun,
                output: output
            )
        }
        renderAndWrite(
            visible: visible,
            statsOnly: statsOnly,
            evidenceByIdentity: evidenceByIdentity,
            effectAnnotations: effectAnnotations
                ? EffectAnnotationAdvice.adviceList(from: pipeline.summaries) : [],
            docstringAdvice: docstringAdvice
                ? Self.docstringAdvice(
                    summaries: pipeline.summaries, suggestions: visible, seedManifest: seedManifest
                ) : [],
            output: output
        )
    }

    /// V1.89 lint pass — extracted from `Discover.run`. Builds the
    /// `InteractiveTriage.Context` and hands off to `runInteractive`.
    /// Same control flow as before the extraction.
    private static func runInteractiveBranch(
        visible: [Suggestion],
        pipeline: PipelineResult,
        directory: URL,
        triageIO: DiscoverInteractiveIO,
        evidenceByIdentity: [String: VerifyEvidence]
    ) throws {
        let packageRoot = pipeline.packageRoot ?? directory
        let context = InteractiveTriage.Context(
            prompt: triageIO.prompt,
            output: triageIO.output,
            diagnostics: triageIO.diagnostics,
            outputDirectory: packageRoot,
            dryRun: triageIO.dryRun,
            proposalsByType: RefactorBridgeOrchestrator.proposals(
                from: visible,
                inverseElementPairs: pipeline.inverseElementPairs
            ),
            equivalenceClassHintsByIdentity: pipeline.equivalenceClassHintsByIdentity,
            consumerProducerChainHintsByIdentity: pipeline.consumerProducerChainHintsByIdentity,
            verifyEvidenceByIdentity: evidenceByIdentity,
            typeShapesByName: pipeline.typeShapesByName
        )
        try runInteractive(suggestions: visible, packageRoot: packageRoot, context: context)
    }
}

/// V1.89 lint pass — small I/O bundle for the interactive-triage path,
/// lifted from the four individual `Discover.run` params (`promptInput`,
/// `output`, `diagnostics`, `dryRun`) so `runInteractiveBranch` stays
/// at 5 params. File-scope rather than nested under `Discover` to keep
/// SwiftLint's nesting cap satisfied.
struct DiscoverInteractiveIO {
    let prompt: any PromptInput
    let output: any DiscoverOutput
    let diagnostics: any DiagnosticOutput
    let dryRun: Bool
}
