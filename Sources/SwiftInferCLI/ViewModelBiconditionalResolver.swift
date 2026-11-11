import Foundation
import SwiftInferCore

/// Biconditional — a Bool flag holds iff a paired Optional is present
/// (paired by a shared name stem: `isLoading` ⟺ `loadingTask`).
public enum ViewModelBiconditionalResolver {
    /// A predicate tying a `Bool` flag to its name-paired Optional's presence, or `nil` if none pair.
    public static func resolve(_ candidate: ViewModelCandidate) -> String? {
        let optionals = candidate.stateFields.filter { ViewModelNameHeuristics.isOptional($0.typeText) }
        for flag in candidate.stateFields where ViewModelNameHeuristics.isBool(flag.typeText) {
            let stem = ViewModelNameHeuristics.booleanStem(flag.name)
            guard stem.count >= 3,
                  let match = optionals.first(where: { $0.name.lowercased().contains(stem) }) else {
                continue
            }
            return "probe.\(flag.name) == (probe.\(match.name) != nil)"
        }
        return nil
    }
}

// Field-shape helpers live in `ViewModelNameHeuristics` (Core), shared with
// `ViewModelInteractionAnalyzer`.
