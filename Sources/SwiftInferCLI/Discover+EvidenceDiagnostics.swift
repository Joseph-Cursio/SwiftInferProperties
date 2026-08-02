import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Run-level reporting for the two **executed**-evidence channels, split out of
/// `Discover+Pipeline.swift` for its file-length cap.
///
/// Both lines exist because a grade change can hide its own reason:
///
/// - The kit demotion drops a 70-point pick to 25, which the default cut hides, so a reader
///   would see `0 suggestions.` and no explanation.
/// - The coverage veto removes a suggestion entirely, so its premise — *PropertyLawKit
///   checks this law* — has never been visible at all, let alone checkable.
///
/// Emitted from **before** the visibility cut. Reporting on survivors would guarantee
/// silence in exactly the cases worth reporting.
extension SwiftInferCommand.Discover {

    static func emitEvidenceDiagnostics(
        graded: [Suggestion],
        artifacts: TemplateRegistry.DiscoverArtifacts,
        evidence: DiscoverEvidenceInputs,
        diagnostics: any DiagnosticOutput
    ) {
        for line in KitEvidenceScoring.diagnostics(for: graded, evidence: evidence.kit) {
            diagnostics.writeDiagnostic("warning: \(line)")
        }
        // `ProtocolCoverageMap` suppresses a law when a conformance means the kit checks it —
        // a claim about a package the project may not depend on, which nothing checked.
        // Recomputed from the same conformance index the veto itself reads, so the audit
        // cannot drift from the decision it audits.
        let findings = ProtocolCoverageAudit.audit(
            inheritedTypesByName: ProtocolCoverageMap.inheritedTypesIndex(
                from: artifacts.typeDecls
            ),
            kitEvidence: evidence.kit
        )
        for line in ProtocolCoverageAudit.diagnostics(for: findings) {
            diagnostics.writeDiagnostic("note: \(line)")
        }
    }
}
