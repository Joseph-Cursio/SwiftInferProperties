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
    /// A predicate that at most one Optional presentation route is set, or `nil` with fewer than two.
    public static func resolve(_ candidate: ViewModelCandidate) -> String? {
        let routes = candidate.stateFields
            .filter {
                ViewModelNameHeuristics.isOptional($0.typeText)
                    && ViewModelNameHeuristics.isPresentationName($0.name)
            }
            .map(\.name)
        guard routes.count >= 2 else { return nil }
        let terms = routes.map { "(probe.\($0) != nil)" }.joined(separator: ", ")
        return "[\(terms)].filter { $0 }.count <= 1"
    }
}
