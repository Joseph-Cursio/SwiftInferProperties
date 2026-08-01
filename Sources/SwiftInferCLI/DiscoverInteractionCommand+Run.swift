import ArgumentParser
import Foundation
import SwiftInferCore

// The two `run` entry points, lifted out of DiscoverInteractionCommand.swift so that file
// stays under SwiftLint's file-length and type-body-length caps — the same split pattern as
// +MultiModule.swift / +ViewModels.swift / +SideOrchestrators.swift. Property wrappers
// (@Option/@Flag) are stored properties and must stay in the primary struct declaration;
// everything else moves here.

extension SwiftInferCommand.DiscoverInteraction {

    /// Directory-level entry point — the real implementation.
    ///
    /// Everything below the CLI works on **directories**; only the label needs to know
    /// whether it came from `--target` (a module name) or `--sources` (an Xcode source
    /// folder, which has no module name to read). Splitting on that is what let `--sources`
    /// reach the interaction families at all: they are the surface built for SwiftUI MVVM
    /// apps, and those are overwhelmingly Xcode projects, so until this existed the one
    /// command aimed at app code was the one that could not open it.
    static func run(
        roots: [TargetDirectory.ScanRoot],
        pinRaw: String? = nil,
        includePossible: Bool = false,
        updateBaseline: Bool = false,
        interactive: Bool = false,
        interactiveBridges: Bool = false,
        dryRun: Bool = false,
        workingDirectory: URL,
        promptInput: any PromptInput = StdinPromptInput(),
        output: any DiscoverOutput,
        diagnostics: any DiagnosticOutput = PrintDiagnosticOutput(),
        firstSeenAt: Date = Date()
    ) throws {
        let suggestions = try collectSuggestions(
            roots: roots,
            pinRaw: pinRaw,
            firstSeenAt: firstSeenAt
        )
        let effectiveFlags = warnAndResolveFlagMutex(
            interactive: interactive,
            interactiveBridges: interactiveBridges,
            updateBaseline: updateBaseline,
            diagnostics: diagnostics
        )
        try dispatchSideOrchestrator(
            suggestions: suggestions,
            inputs: SideOrchestratorInputs(
                effectiveFlags: effectiveFlags,
                workingDirectory: workingDirectory,
                target: roots.map(\.label).joined(separator: ", "),
                promptInput: promptInput,
                output: output,
                diagnostics: diagnostics,
                dryRun: dryRun,
                firstSeenAt: firstSeenAt
            )
        )
        let graded = gradedByVerifyEvidence(
            suggestions,
            workingDirectory: workingDirectory,
            diagnostics: diagnostics
        )
        let rendered = InteractionSuggestionRenderer.render(
            graded,
            includePossible: includePossible
        )
        output.write(rendered)
    }

    /// Multi-module variant keyed by SwiftPM target name. Forwards to `run(roots:)`; kept
    /// because `drift-interaction`, `accept-interaction` and the suites name it.
    public static func run(
        targets: [String],
        pinRaw: String? = nil,
        includePossible: Bool = false,
        updateBaseline: Bool = false,
        interactive: Bool = false,
        interactiveBridges: Bool = false,
        dryRun: Bool = false,
        workingDirectory: URL,
        promptInput: any PromptInput = StdinPromptInput(),
        output: any DiscoverOutput,
        diagnostics: any DiagnosticOutput = PrintDiagnosticOutput(),
        firstSeenAt: Date = Date()
    ) throws {
        try run(
            roots: targets.map { name in
                TargetDirectory.ScanRoot(
                    label: name,
                    directory: workingDirectory
                        .appendingPathComponent("Sources")
                        .appendingPathComponent(name)
                )
            },
            pinRaw: pinRaw,
            includePossible: includePossible,
            updateBaseline: updateBaseline,
            interactive: interactive,
            interactiveBridges: interactiveBridges,
            dryRun: dryRun,
            workingDirectory: workingDirectory,
            promptInput: promptInput,
            output: output,
            diagnostics: diagnostics,
            firstSeenAt: firstSeenAt
        )
    }
}
