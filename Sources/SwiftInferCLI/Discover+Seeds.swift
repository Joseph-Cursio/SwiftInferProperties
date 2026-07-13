import ArgumentParser
import Foundation
import SwiftInferCore

/// `swift-infer discover --seeds` — the consumer side of the lint → infer
/// pipeline. SwiftProjectLint's `--format pbt-seeds` names the functions worth
/// property-testing; these helpers load that manifest and focus discovery's
/// output down to exactly those functions.
extension SwiftInferCommand.Discover {

    /// Loads and decodes a `pbt-seeds` manifest. Throws a readable error when
    /// the file is absent or malformed: `--seeds` is an explicit focusing
    /// request, so failing loudly beats silently emitting the full, unfocused
    /// result in a pipeline.
    static func loadSeedManifest(at url: URL) throws -> SeedManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ValidationError("could not read seeds file at \(url.path): \(error.localizedDescription)")
        }
        do {
            return try JSONDecoder().decode(SeedManifest.self, from: data)
        } catch {
            throw ValidationError("could not parse seeds file at \(url.path) as a pbt-seeds manifest: \(error)")
        }
    }

    /// Applies the `--seeds` focus. With no manifest this is the identity. With
    /// one, it keeps only suggestions touching a seeded function, warns on an
    /// unknown schema version, and reports the focus ratio to stderr so stdout
    /// stays a clean suggestion stream.
    ///
    /// The two ways focusing can silently destroy the run get a loud warning each, because a
    /// tool that answers "0 suggestions" when it found several is worse than a tool that answers
    /// nothing at all — the reader believes it.
    static func focus(
        _ pipeline: PipelineResult,
        with seedManifest: SeedManifest?,
        diagnostics: any DiagnosticOutput
    ) -> [Suggestion] {
        guard let seedManifest else { return pipeline.suggestions }
        if seedManifest.version != SeedManifest.supportedVersion {
            diagnostics.writeDiagnostic(
                "warning: seeds manifest version \(seedManifest.version) is not the supported "
                    + "version \(SeedManifest.supportedVersion); consuming best-effort"
            )
        }

        // Say what a human must do before any tool can help. These seeds never focus — see below.
        reportRefactorPending(in: seedManifest, diagnostics: diagnostics)

        let focusing = seedManifest.analysableSeeds
        let analysableManifest = SeedManifest(version: seedManifest.version, seeds: focusing)

        // No *analysable* seed is not a request to see nothing. There are two ways to arrive here
        // and the reader needs to be told which, because the remedy differs.
        if focusing.isEmpty {
            diagnostics.writeDiagnostic(noFocusWarning(for: seedManifest, pipeline: pipeline))
            return pipeline.suggestions + synthesizeGenericLaws(
                for: analysableManifest,
                summaries: pipeline.summaries,
                covered: pipeline.suggestions,
                diagnostics: diagnostics,
                restrictedFunctions: pipeline.restrictedFunctions
            )
        }

        let focused = SeedFocus.filter(pipeline.suggestions, to: analysableManifest)
        diagnostics.writeDiagnostic(
            "focused on \(focusing.count) analysable seed(s): kept \(focused.count) "
                + "of \(pipeline.suggestions.count) suggestion(s)"
        )

        // Seeds that match nothing are the other way to end up at a confident zero. The focus is
        // honoured — the user asked for it — but they are told it emptied the run, and why.
        if focused.isEmpty, !pipeline.suggestions.isEmpty {
            diagnostics.writeDiagnostic(
                "warning: none of the \(focusing.count) analysable seed(s) matched any of the "
                    + "\(pipeline.suggestions.count) suggestion(s) found, so the focus discarded "
                    + "all of them. The join is on (file basename, bare symbol) — a mismatch here "
                    + "usually means the linter and swift-infer disagree about which functions are "
                    + "candidates. Re-run without --seeds to see what was discarded."
            )
        }
        // Broaden: a seeded pure function that no template matched still earns
        // the generic determinism law, so `--seeds` always surfaces something.
        let generic = synthesizeGenericLaws(
            for: analysableManifest,
            summaries: pipeline.summaries,
            covered: focused,
            diagnostics: diagnostics,
            restrictedFunctions: pipeline.restrictedFunctions
        )
        return focused + generic
    }

    /// The two ways a manifest can carry no *analysable* seed, told apart — because "the linter
    /// found nothing" and "the linter found only work you have to do first" call for opposite next
    /// steps, and a single message for both would send half of its readers the wrong way.
    private static func noFocusWarning(
        for seedManifest: SeedManifest,
        pipeline: PipelineResult
    ) -> String {
        let shown = "no focus was applied and all \(pipeline.suggestions.count) suggestion(s) "
            + "are shown."

        guard !seedManifest.seeds.isEmpty else {
            return "warning: the seeds manifest is empty, so \(shown) An empty manifest usually "
                + "means the producing linter found no candidates — not that this code has none. "
                + "If the linter cannot see the shape of your code (instance methods, for one), "
                + "seed it by hand or re-run without --seeds."
        }

        return "warning: all \(seedManifest.seeds.count) seed(s) in the manifest name work that "
            + "must be done by hand first — not a function this tool can analyse — so \(shown) "
            + "Extract the kernels listed above into named functions and re-run the linter; they "
            + "will come back as ordinary seeds, and their laws with them."
    }

    /// Announce the seeds that name pure logic with **no name yet**.
    ///
    /// This is the whole reason `kind` exists. A kernel cannot be focused on — its symbol is the
    /// impure method the logic is trapped inside, so narrowing to it would make this tool refuse the
    /// function and report `kept 0` for code that demonstrably has property-testable logic in it.
    /// Silently skipping them would be no better: the reader would see a smaller number and no
    /// reason for it.
    ///
    /// So they are neither focused on nor dropped. They are *named*, with the one instruction that
    /// unblocks them.
    private static func reportRefactorPending(
        in seedManifest: SeedManifest,
        diagnostics: any DiagnosticOutput
    ) {
        let pending = seedManifest.refactorPendingSeeds
        guard !pending.isEmpty else { return }

        let kernels = pending.filter { $0.kind == .extractableKernel }
        let unknown = pending.filter { seed in
            if case .unrecognised = seed.kind { return true }
            return false
        }

        if !kernels.isEmpty {
            diagnostics.writeDiagnostic(
                "\(kernels.count) extractable kernel(s) — pure logic with no name yet, so there is "
                    + "nothing here to index, call, or generate inputs for. No law can be proposed "
                    + "until a human draws the boundary:"
            )
            for seed in kernels {
                diagnostics.writeDiagnostic(
                    "  \(seed.file):\(seed.line): inside `\(seed.symbol)` — extract it into a "
                        + "named value type, then re-run the linter to seed it properly."
                )
            }
        }

        for seed in unknown {
            diagnostics.writeDiagnostic(
                "warning: seed `\(seed.symbol)` (\(seed.file):\(seed.line)) has kind "
                    + "'\(seed.kind.rawValue)', which this build does not recognise. It was NOT "
                    + "focused on: narrowing to a symbol whose meaning is unknown is how a tool "
                    + "ends up reporting a confident zero. Upgrade swift-infer, or re-run without "
                    + "--seeds."
            )
        }
    }
}
