import Foundation
import SwiftInferCore

/// PROTOTYPE — predicate resolvers for the three remaining state-invariant
/// families (cardinality / biconditional / conservation). Each derives the
/// invariant predicate over a `probe` instance from the view model's State
/// surface; the shared `ViewModelInvariantStubEmitter` then checks it after
/// every driven action. `nil` = no verifiable shape on this view model.
/// (Referential integrity lives in `ViewModelRefintResolver`.)

/// Cardinality — ≥2 Optional presentation routes are mutually exclusive
/// (at most one active at a time).
public enum ViewModelCardinalityResolver {
    public static func resolve(_ candidate: ViewModelCandidate) -> String? {
        let routes = candidate.stateFields
            .filter { ViewModelNameHeuristics.isOptional($0.typeText) && ViewModelNameHeuristics.isPresentationName($0.name) }
            .map(\.name)
        guard routes.count >= 2 else { return nil }
        let terms = routes.map { "(probe.\($0) != nil)" }.joined(separator: ", ")
        return "[\(terms)].filter { $0 }.count <= 1"
    }
}

/// Biconditional — a Bool flag holds iff a paired Optional is present
/// (paired by a shared name stem: `isLoading` ⟺ `loadingTask`).
public enum ViewModelBiconditionalResolver {
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

/// Conservation — a `*count*` Int field tracks a sibling collection's size.
public enum ViewModelConservationResolver {
    public static func resolve(_ candidate: ViewModelCandidate) -> String? {
        guard let collection = candidate.stateFields.first(where: { ViewModelNameHeuristics.isCollection($0.typeText) }),
              let counter = candidate.stateFields.first(where: {
                  $0.name.lowercased().contains("count") && ViewModelNameHeuristics.stripOptional($0.typeText) == "Int"
              }) else {
            return nil
        }
        return "probe.\(counter.name) == probe.\(collection.name).count"
    }
}

// Field-shape helpers live in `ViewModelNameHeuristics` (Core), shared with
// `ViewModelInteractionAnalyzer`.
