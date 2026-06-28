import Foundation
import SwiftInferCore

/// `swift-infer discover` orchestration helpers — rendering the surviving
/// suggestions and loading persisted `verify` evidence. Extracted from
/// `SwiftInferCommand.swift` so the command file stays under SwiftLint's
/// file- and type-body-length caps; behavior is unchanged.
extension SwiftInferCommand.Discover {

    /// V1.89 lint pass — render branch extracted from `Discover.run`
    /// so the orchestrator body stays under SwiftLint's 50-line cap.
    /// V1.64.C annotation behavior unchanged: when `evidenceByIdentity`
    /// is empty, blocks render byte-identically to the pre-v1.64 output.
    static func renderAndWrite(
        visible: [Suggestion],
        statsOnly: Bool,
        evidenceByIdentity: [String: VerifyEvidence],
        output: any DiscoverOutput
    ) {
        let rendered: String
        if statsOnly {
            rendered = SuggestionRenderer.renderStats(visible)
        } else {
            rendered = SuggestionRenderer.render(
                visible,
                verifyEvidenceByIdentity: evidenceByIdentity
            )
        }
        output.write(rendered)
    }

    /// V1.67 — load persisted `swift-infer verify` evidence so it
    /// feeds the pipeline's scoring AND its visibility filter:
    /// `bothPass` raises the score (and can lift a pick past the
    /// visibility threshold), `defaultFails` vetoes → `.suppressed`
    /// → dropped by the pipeline's own filter. The returned map
    /// is reused for the V1.64.C render-time annotation.
    ///
    /// V1.89 lint pass — extracted from `Discover.run` so the
    /// orchestrator body stays under SwiftLint's 50-line cap.
    static func loadVerifyEvidenceMap(
        directory: URL,
        diagnostics: any DiagnosticOutput
    ) -> [String: VerifyEvidence] {
        let evidenceResult = VerifyEvidenceStore.load(startingFrom: directory)
        for warning in evidenceResult.warnings {
            diagnostics.writeDiagnostic("warning: \(warning)")
        }
        return Dictionary(
            evidenceResult.log.records.map { ($0.identityHash, $0) }
        ) { _, latest in latest }
    }
}
