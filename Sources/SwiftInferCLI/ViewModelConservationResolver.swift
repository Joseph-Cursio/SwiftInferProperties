import Foundation
import SwiftInferCore

/// Conservation — a `*count*` Int field tracks a sibling collection's size.
public enum ViewModelConservationResolver {
    /// A predicate that a `count` `Int` field equals a sibling collection's `count`, or `nil`.
    public static func resolve(_ candidate: ViewModelCandidate) -> String? {
        guard let collection = candidate.stateFields.first(where: {
            ViewModelNameHeuristics.isCollection($0.typeText)
        }),
              let counter = candidate.stateFields.first(where: {
                  $0.name.lowercased().contains("count") && ViewModelNameHeuristics.stripOptional($0.typeText) == "Int"
              }) else {
            return nil
        }
        return "probe.\(counter.name) == probe.\(collection.name).count"
    }
}
