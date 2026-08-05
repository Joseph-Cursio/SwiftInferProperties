import Foundation
import SwiftInferCore

/// `index --seeds` — the half of the lint→infer loop that lets verify check what
/// discovery actually found.
///
/// Split out at the 400-line cap, and the seam is meaningful: everything here is
/// about **which population an index describes**, which is the distinction whose
/// absence let `verify --all-from-index` silently answer about a different set
/// than the seed hop produced.
extension SwiftInferCommand.Index {

    /// Apply the seed manifest, or hand the pipeline back untouched.
    ///
    /// Returns a `PipelineResult` whose `suggestions` are the focused set and whose shape
    /// maps are unchanged: verify needs the WHOLE type universe to resolve generators even
    /// for a narrowed entry list, and filtering the shapes alongside the suggestions would
    /// reintroduce the carrier-decline flood the `allShapes` threading exists to prevent.
    static func seedFocused(
        _ pipeline: SwiftInferCommand.Discover.PipelineResult,
        inputs: IndexInputs,
        diagnostics: any DiagnosticOutput
    ) throws -> SwiftInferCommand.Discover.PipelineResult {
        guard let seedPath = inputs.seedManifestPath else { return pipeline }
        let manifest = try SwiftInferCommand.Discover.loadSeedManifest(at: seedPath)
        let focused = SwiftInferCommand.Discover.focus(pipeline, with: manifest, diagnostics: diagnostics)
        return pipeline.replacingSuggestions(focused)
    }
}
