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
            .filter { vmIsOptional($0.typeText) && vmIsPresentationName($0.name) }
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
        let optionals = candidate.stateFields.filter { vmIsOptional($0.typeText) }
        for flag in candidate.stateFields where vmIsBool(flag.typeText) {
            let stem = vmBooleanStem(flag.name)
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
        guard let collection = candidate.stateFields.first(where: { vmIsCollection($0.typeText) }),
              let counter = candidate.stateFields.first(where: {
                  $0.name.lowercased().contains("count") && vmStripOptional($0.typeText) == "Int"
              }) else {
            return nil
        }
        return "probe.\(counter.name) == probe.\(collection.name).count"
    }
}

// MARK: - Field-shape helpers (verify-side, self-contained)

func vmIsOptional(_ type: String) -> Bool {
    type.hasSuffix("?")
}

func vmIsBool(_ type: String) -> Bool {
    vmStripOptional(type) == "Bool"
}

func vmIsCollection(_ type: String) -> Bool {
    let base = vmStripOptional(type)
    return base.hasPrefix("[")
        || base.contains("Set<") || base.contains("Array<")
        || base.contains("Dictionary<") || base.contains("IdentifiedArray")
}

func vmIsPresentationName(_ name: String) -> Bool {
    let lowered = name.lowercased()
    return ["sheet", "alert", "popover", "route", "destination", "presented", "cover", "dialog"]
        .contains { lowered.contains($0) }
}

/// Strip a Bool's `is`/`has`/`show`/`should`/… prefix to its stem, lowercased.
func vmBooleanStem(_ name: String) -> String {
    let lowered = name.lowercased()
    for prefix in ["isshowing", "is", "has", "show", "should", "did", "will"]
    where lowered.hasPrefix(prefix) && lowered.count > prefix.count {
        return String(lowered.dropFirst(prefix.count))
    }
    return lowered
}

func vmStripOptional(_ type: String) -> String {
    var trimmed = type.trimmingCharacters(in: .whitespaces)
    while trimmed.hasSuffix("?") || trimmed.hasSuffix("!") {
        trimmed = String(trimmed.dropLast())
    }
    return trimmed.trimmingCharacters(in: .whitespaces)
}
