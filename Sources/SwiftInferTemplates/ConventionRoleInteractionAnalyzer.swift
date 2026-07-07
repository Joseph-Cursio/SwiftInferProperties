import Foundation
import SwiftInferCore

/// PROTOTYPE — surfaces the `outputDeterminism` candidate invariant for a
/// convention role (VIPER interactor / MVP presenter) as a production
/// `InteractionInvariantSuggestion`, so VIPER/MVP roles flow through the same
/// `discover-interaction` render / scoring / drift pipeline as reducers and MVVM
/// view models (the MVVM-carrier productionization pattern, applied to the
/// convention carrier).
///
/// A role qualifies iff it has an assertable **output collaborator** (the
/// protocol it pushes results to) — that's the surface `outputDeterminism`
/// reasons about. All `.possible` / unverified — a new inference *source*, so it
/// ships at default-Possible visibility per PRD §3.5 (hidden until
/// `--include-possible`). Measured verification is the dedicated recording-fake
/// harness (`OutputDeterminismVerifierEmitter`), joined in a later slice.
public enum ConventionRoleInteractionAnalyzer {

    public static func suggestions(
        for role: StatefulRole,
        firstSeenAt: Date
    ) -> [InteractionInvariantSuggestion] {
        guard let output = outputCollaborator(of: role) else { return [] }
        return [makeSuggestion(role: role, output: output, firstSeenAt: firstSeenAt)]
    }

    /// The assertable output collaborator, if any.
    static func outputCollaborator(of role: StatefulRole) -> Collaborator? {
        role.collaborators.first { collaborator in
            if case .output = collaborator.role { return true }
            return false
        }
    }

    private static func makeSuggestion(
        role: StatefulRole,
        output: Collaborator,
        firstSeenAt: Date
    ) -> InteractionInvariantSuggestion {
        let rationale = "the role's calls to its output collaborator "
            + "'\(output.propertyName): \(output.protocolType)' should be deterministic "
            + "given the same input — running it twice must produce the identical output-call log"
        let identity = SuggestionIdentity(
            canonicalInput: InteractionInvariantSuggestion.identityCanonicalInput(
                family: .outputDeterminism,
                reducerQualifiedName: role.typeName,
                predicate: output.propertyName
            )
        )
        let actionList = role.actions.map(\.name).joined(separator: ", ")
        return InteractionInvariantSuggestion(
            identity: identity,
            family: .outputDeterminism,
            reducerQualifiedName: role.typeName,
            reducerLocation: role.location,
            stateTypeName: role.typeName,
            actionTypeName: role.typeName,
            predicate: rationale,
            score: 30,
            tier: .possible,
            whySuggested: [
                "\(role.paradigm.rawValue.uppercased()) convention role (by naming/conformance)",
                rationale,
                "output collaborator: \(output.propertyName): \(output.protocolType)",
                actionList.isEmpty ? "actions: (none detected)" : "actions: \(actionList)"
            ],
            whyMightBeWrong: [
                "Surfaced from the role's output collaborator by convention — unverified "
                    + "(default Possible per §3.5).",
                "Measured verification requires constructing the role (its non-output protocol "
                    + "dependencies must be fakeable) and recording the output protocol's calls; "
                    + "async / throws output requirements are not yet recordable."
            ],
            firstSeenAt: firstSeenAt
        )
    }
}
