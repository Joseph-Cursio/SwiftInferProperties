import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Productionization — folds SwiftUI MVVM view models into the
/// `discover-interaction` pipeline. `ViewModelDiscoverer` recognises
/// `@Observable` / `ObservableObject` classes, and
/// `ViewModelInteractionAnalyzer.suggestions` maps their candidate
/// invariants onto `InteractionInvariantSuggestion`s (at default-Possible,
/// a new inference source per PRD §3.5), so they render / score / drift
/// through the same path as reducer-derived suggestions. File-scope
/// extension to keep `DiscoverInteractionCommand.swift` under the
/// SwiftLint file-length cap.
extension SwiftInferCommand.DiscoverInteraction {

    static func mergedWithViewModels(
        _ reducerSuggestions: [InteractionInvariantSuggestion],
        directory: URL,
        firstSeenAt: Date
    ) throws -> [InteractionInvariantSuggestion] {
        let viewModels = try ViewModelDiscoverer.discover(directory: directory)
        let viewModelSuggestions = viewModels.flatMap {
            ViewModelInteractionAnalyzer.suggestions(for: $0, firstSeenAt: firstSeenAt)
        }
        return (reducerSuggestions + viewModelSuggestions).sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.identity.normalized < rhs.identity.normalized
        }
    }
}
