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
    /// Now a thin forwarder — the body moved to `TargetDirectory.resolveScan(target:sources:)` so
    /// the other scanning commands could stop being SwiftPM-only. It stays because callers and
    /// tests name it, and because `Discover` is where the escape hatch was first argued for.
    public static func resolveScanDirectory(target: String?, sources: String?) throws -> URL {
        try TargetDirectory.resolveScan(target: target, sources: sources)
    }

    public func run() async throws {
        // Infers the scope when neither flag is given, rather than erroring — the lint→infer
        // hop's first-attempt failure. Only `discover` does this; see
        // `TargetDirectory.resolveScanInferring` for why the other scanning commands keep the
        // loud error, and why the several-modules case scans everything instead of picking one.
        let scan = try TargetDirectory.resolveScanInferring(target: target, sources: sources)
        if let note = scan.note {
            FileHandle.standardError.write(Data("note: \(note)\n".utf8))
        }
        let directory = scan.directory
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
            requireCorroboration: requireCorroboration,
            resolveEffects: resolveEffects,
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
        docstringAdvice: Bool? = nil,
        dryRun: Bool = false,
        interactive: Bool = false,
        updateBaseline: Bool = false,
        seedManifest: SeedManifest? = nil,
        requireCorroboration: Bool = false,
        resolveEffects: Bool = false,
        promptInput: any PromptInput = StdinPromptInput(),
        output: any DiscoverOutput,
        diagnostics: any DiagnosticOutput = PrintDiagnosticOutput()
    ) throws {
        let evidence = loadEvidence(directory: directory, diagnostics: diagnostics)
        // The manifest reaches the pipeline as well as the focus below, because a seed naming an
        // access-restricted function must rescue it into template ANALYSIS — which happens inside
        // the pipeline — and not merely survive the focus applied to the pipeline's result.
        let pipeline = try collectVisibleSuggestions(
            directory: directory,
            includePossible: includePossible,
            docstringAdvice: docstringAdvice,
            explicitVocabularyPath: explicitVocabularyPath,
            explicitConfigPath: explicitConfigPath,
            explicitTestDirectory: explicitTestDirectory,
            packsOverride: packsOverride,
            evidence: evidence,
            seedManifest: seedManifest,
            requireCorroboration: requireCorroboration,
            resolveEffects: resolveEffects,
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
                triageIO: interactiveIO(
                    prompt: promptInput, output: output, dryRun: dryRun, diagnostics: diagnostics
                ),
                evidenceByIdentity: evidence.verifyByIdentity
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
        renderTerminalOutput(
            visible: visible,
            context: RenderContext(
                pipeline: pipeline,
                evidence: evidence,
                seedManifest: seedManifest,
                statsOnly: statsOnly,
                effectAnnotations: effectAnnotations
            ),
            output: output
        )
    }

    /// Everything the rendering tail needs that is not the suggestion list.
    ///
    /// Bundled rather than passed loose so the extraction stays inside both the
    /// `function_parameter_count` cap and the `function_body_length` cap it was
    /// made to satisfy. The grouping is not arbitrary: all four are *context*
    /// about the run, and the two switches in particular gate advisory sections
    /// that never enter accept / verify.
    struct RenderContext {
        let pipeline: PipelineResult
        let evidence: DiscoverEvidenceInputs
        let seedManifest: SeedManifest?
        let statsOnly: Bool
        let effectAnnotations: Bool
    }

    /// The default (non-interactive, non-baseline) rendering tail.
    ///
    /// Extracted when `--resolve-effects` pushed `run` one line past the
    /// `function_body_length` cap. The seam is the natural one rather than an
    /// arithmetic split: everything above decides WHAT to show, this decides how
    /// to show it.
    private static func renderTerminalOutput(
        visible: [Suggestion],
        context: RenderContext,
        output: any DiscoverOutput
    ) {
        let pipeline = context.pipeline
        // Only the evidence that is actually about the code being rendered. The RAW map here
        // was a real defect: `render` derives the displayed tier via
        // `promoted(byVerifyOutcome:)`, so a row whose `+50` the staleness gate had correctly
        // withheld still printed `Verified` — directly above its own caveat saying the
        // evidence was not being applied. Measured at 4 rows on `SwiftInferCore` the day the
        // gate shipped. Scoring and rendering must not be able to disagree, so both go
        // through `VerifyEvidenceScoring`.
        let applicableEvidence = VerifyEvidenceScoring.applicable(
            to: visible,
            evidenceByIdentity: context.evidence.verifyByIdentity,
            currentFingerprintByIdentity: fingerprintsByIdentity(
                for: visible, summaries: pipeline.summaries
            )
        )
        renderAndWrite(
            visible: visible,
            statsOnly: context.statsOnly,
            evidenceByIdentity: applicableEvidence,
            effectAnnotations: context.effectAnnotations
                ? EffectAnnotationAdvice.adviceList(from: pipeline.summaries) : [],
            docstringAdvice: docstringAdviceIfEnabled(
                pipeline: pipeline, visible: visible, seedManifest: context.seedManifest
            ),
            refutedLaws: pipeline.refutedLaws,
            coverage: pipeline.coverage,
            output: output
        )
    }

    /// The docstring advisory, or nothing when it is switched off.
    ///
    /// The effective setting rides on `PipelineResult` rather than being re-read
    /// here, because the pipeline has already loaded the config — this keeps the
    /// CLI > config > default precedence in one place (`resolvePipelineSetup`)
    /// and saves a second `ConfigLoader.load`.
    private static func docstringAdviceIfEnabled(
        pipeline: PipelineResult,
        visible: [Suggestion],
        seedManifest: SeedManifest?
    ) -> [DocstringAdviceItem] {
        guard pipeline.docstringAdvice else { return [] }
        return docstringAdvice(
            summaries: pipeline.summaries, suggestions: visible, seedManifest: seedManifest
        )
    }

    /// Gather `run`'s four loose IO arguments into the struct that already exists for them.
    ///
    /// Extracted because threading the seed manifest into the pipeline put `Discover.run` one
    /// line over the 50-line body cap. A wrapper taking all eight arguments was tried first and
    /// tripped `function_parameter_count` — which was the rule making the right point: the thing
    /// worth naming here is the IO bundle, not another pass-through.
    private static func interactiveIO(
        prompt: any PromptInput,
        output: any DiscoverOutput,
        dryRun: Bool,
        diagnostics: any DiagnosticOutput
    ) -> DiscoverInteractiveIO {
        DiscoverInteractiveIO(
            prompt: prompt,
            output: output,
            diagnostics: diagnostics,
            dryRun: dryRun
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
