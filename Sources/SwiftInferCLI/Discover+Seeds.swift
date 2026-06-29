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
        let focused = SeedFocus.filter(pipeline.suggestions, to: seedManifest)
        diagnostics.writeDiagnostic(
            "focused on \(seedManifest.seeds.count) seed(s): kept \(focused.count) "
                + "of \(pipeline.suggestions.count) suggestion(s)"
        )
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
