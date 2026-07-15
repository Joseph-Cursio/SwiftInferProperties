import Foundation
import SwiftInferCore

/// The non-empty-focus path of `discover --seeds`, split out of
/// `Discover+Seeds.swift` to keep that file within the length limit and `focus`
/// within the body-length limit. The two loud "silent zero" warnings stay one on
/// each side of the split — the empty-focus warning in `focus`, the no-match
/// warning here — because each guards a different way the focus can quietly
/// destroy the run.
extension SwiftInferCommand.Discover {

    /// At least one analysable seed: honour the focus, but never discard a law
    /// the code OWES (`keepRoleEntailedLaws`) or a real law the tier cut merely
    /// hid (`promoteTierHiddenLaws`), and always broaden with the generic
    /// determinism fallback so `--seeds` surfaces something.
    static func focusOnAnalysableSeeds(
        focusing: [SeedManifest.Seed],
        analysableManifest: SeedManifest,
        pipeline: PipelineResult,
        diagnostics: any DiagnosticOutput
    ) -> [Suggestion] {
        let focused = SeedFocus.filter(pipeline.suggestions, to: analysableManifest)

        // A seed-independent law was never *in* the search the seeds narrow — its subject is impure,
        // and a pure-function manifest cannot name one. Counting it as a "seed match" would be a lie,
        // and filtering it out would throw away the only law in the run that can fail.
        let exempt = SeedFocus.seedIndependent(in: focused)
        let matched = focused.count - exempt.count

        diagnostics.writeDiagnostic(
            "focused on \(focusing.count) analysable seed(s): kept \(matched) "
                + "of \(pipeline.suggestions.count - exempt.count) seedable suggestion(s)"
        )

        if !exempt.isEmpty {
            diagnostics.writeDiagnostic(
                "kept \(exempt.count) law(s) no seed manifest could name — their subjects are impure "
                    + "(a state machine's moves are `Void`-returning mutators), so the linter's "
                    + "pure-function rule can never seed them. They were never in the search the "
                    + "seeds narrow, so the focus does not get to discard them."
            )
        }

        // Seeds that match nothing are the other way to end up at a confident zero. The focus is
        // honoured — the user asked for it — but they are told it emptied the run, and why.
        let seedableFound = pipeline.suggestions.count - exempt.count
        if matched == 0, seedableFound > 0 {
            diagnostics.writeDiagnostic(
                "warning: none of the \(focusing.count) analysable seed(s) matched any of the "
                    + "\(seedableFound) seedable suggestion(s) found, so the focus discarded "
                    + "all of them. The join is on (file basename, bare symbol) — a mismatch here "
                    + "usually means the linter and swift-infer disagree about which functions are "
                    + "candidates."
            )
        }

        // A law the code OWES is never discarded for want of a seed.
        let owed = keepRoleEntailedLaws(
            in: pipeline.suggestions,
            alreadyShown: focused,
            diagnostics: diagnostics
        )

        // A seeded function whose real law the tier cut hid does not get a tautology instead.
        let promoted = promoteTierHiddenLaws(
            for: analysableManifest,
            pipeline: pipeline,
            alreadyShown: focused + owed,
            diagnostics: diagnostics
        )

        // Broaden: a seeded pure function that no template matched still earns
        // the generic determinism law, so `--seeds` always surfaces something.
        let covered = focused + owed + promoted
        let generic = synthesizeGenericLaws(
            for: analysableManifest,
            summaries: pipeline.summaries,
            covered: covered,
            diagnostics: diagnostics,
            restrictedFunctions: pipeline.restrictedFunctions
        )
        return guardFinalAnswer(covered + generic, pipeline: pipeline, diagnostics: diagnostics)
    }
}
