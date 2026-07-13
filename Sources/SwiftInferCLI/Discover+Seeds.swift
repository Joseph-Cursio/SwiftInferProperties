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

        // An empty manifest is not a request to see nothing — it is what a producer that found
        // nothing looks like. Filtering on it would throw away every real suggestion and report
        // the result as an honest zero.
        if seedManifest.seeds.isEmpty {
            diagnostics.writeDiagnostic(
                "warning: the seeds manifest is empty, so no focus was applied and all "
                    + "\(pipeline.suggestions.count) suggestion(s) are shown. An empty manifest "
                    + "usually means the producing linter found no candidates — not that this "
                    + "code has none. If the linter cannot see the shape of your code (instance "
                    + "methods, for one), seed it by hand or re-run without --seeds."
            )
            return pipeline.suggestions + synthesizeGenericLaws(
                for: seedManifest,
                summaries: pipeline.summaries,
                covered: pipeline.suggestions,
                diagnostics: diagnostics
            )
        }

        let focused = SeedFocus.filter(pipeline.suggestions, to: seedManifest)
        diagnostics.writeDiagnostic(
            "focused on \(seedManifest.seeds.count) seed(s): kept \(focused.count) "
                + "of \(pipeline.suggestions.count) suggestion(s)"
        )

        // Seeds that match nothing are the other way to end up at a confident zero. The focus is
        // honoured — the user asked for it — but they are told it emptied the run, and why.
        if focused.isEmpty, !pipeline.suggestions.isEmpty {
            diagnostics.writeDiagnostic(
                "warning: none of the \(seedManifest.seeds.count) seed(s) matched any of the "
                    + "\(pipeline.suggestions.count) suggestion(s) found, so the focus discarded "
                    + "all of them. The join is on (file basename, bare symbol) — a mismatch here "
                    + "usually means the linter and swift-infer disagree about which functions are "
                    + "candidates. Re-run without --seeds to see what was discarded."
            )
        }
        // Broaden: a seeded pure function that no template matched still earns
        // the generic determinism law, so `--seeds` always surfaces something.
        let generic = synthesizeGenericLaws(
            for: seedManifest,
            summaries: pipeline.summaries,
            covered: focused,
            diagnostics: diagnostics
        )
        return focused + generic
    }
}
