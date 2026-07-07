import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Productionization — folds convention roles (VIPER interactors / MVP
/// presenters) into the `discover-interaction` pipeline. `ConventionRoleDiscoverer`
/// recognises them by naming/conformance, and `ConventionRoleInteractionAnalyzer.suggestions`
/// maps each role's assertable output collaborator onto an `outputDeterminism`
/// `InteractionInvariantSuggestion` (at default-Possible, a new inference source
/// per PRD §3.5), so they render / score / drift through the same path as reducer
/// and MVVM suggestions. File-scope extension to keep the primary command file
/// under the SwiftLint file-length cap (the `mergedWithViewModels` precedent).
extension SwiftInferCommand.DiscoverInteraction {

    static func mergedWithConventionRoles(
        _ existing: [InteractionInvariantSuggestion],
        directory: URL,
        firstSeenAt: Date
    ) throws -> [InteractionInvariantSuggestion] {
        let roles = try ConventionRoleDiscoverer.discover(directory: directory)
        let roleSuggestions = roles.flatMap {
            ConventionRoleInteractionAnalyzer.suggestions(for: $0, firstSeenAt: firstSeenAt)
        }
        return (existing + roleSuggestions).sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.identity.normalized < rhs.identity.normalized
        }
    }
}
