import SwiftInferCore

/// PROTOTYPE — statically surfaces candidate interaction invariants over a
/// recognised `ViewModelCandidate` (its action alphabet + State surface),
/// reusing the same five families the reducer pipeline runs but reading
/// them off the already-extracted MVVM shape instead of re-walking a
/// reducer's State/Action source. Every candidate is unverified
/// (`.possible`) — execution (a future witness strategy that *constructs*
/// the view model) decides. This is the discovery half of the MVVM
/// carrier; the verify half is the larger, separate lift.
///
/// **Family heuristics (prototype, conservative):**
///   - **Idempotence** — an action whose name matches the shared
///     idempotence witness vocabulary (`IdempotenceWitnessDetector.classify`:
///     exact `dismiss`/`reset`/`select`/… + prefix `set*`/`select*`/…).
///     Reuses the production classifier verbatim.
///   - **Referential integrity** — a `selected*` State field should
///     reference an element of a sibling collection (or be empty/nil).
///   - **Conservation** — a `*count*` field tracks the size of a sibling
///     collection.
///   - **Cardinality** — ≥2 Optional presentation fields (`*sheet*`,
///     `*alert*`, `*route*`, `*presented*`, …) are mutually exclusive.
///   - **Biconditional** — a Bool flag and an Optional that share a name
///     stem (`isLoading` ⟺ `loadingData != nil`).
public enum ViewModelInteractionAnalyzer {

    public static func analyze(_ candidate: ViewModelCandidate) -> [ViewModelInteractionCandidate] {
        var out: [ViewModelInteractionCandidate] = []
        out.append(contentsOf: idempotence(candidate))
        out.append(contentsOf: referentialIntegrity(candidate))
        out.append(contentsOf: conservation(candidate))
        out.append(contentsOf: cardinality(candidate))
        out.append(contentsOf: biconditional(candidate))
        return out
    }

    // MARK: - Idempotence (action-name vocabulary — reuses the detector)

    private static func idempotence(_ candidate: ViewModelCandidate) -> [ViewModelInteractionCandidate] {
        candidate.actions.compactMap { action in
            guard let kind = IdempotenceWitnessDetector.classify(action.name) else { return nil }
            let how = kind == .exactName ? "exact-name" : "name-prefix"
            return ViewModelInteractionCandidate(
                family: .idempotence,
                typeName: candidate.typeName,
                subjects: [action.signature],
                rationale: "action '\(action.name)' matches the idempotence vocabulary "
                    + "(\(how)) — applying it twice should equal applying it once"
            )
        }
    }

    // MARK: - Referential integrity (selected* ↔ collection)

    private static func referentialIntegrity(
        _ candidate: ViewModelCandidate
    ) -> [ViewModelInteractionCandidate] {
        let collections = candidate.stateFields.filter { isCollection($0.typeText) }
        let sources = collections
            .map(\.name)
            .filter { !isSelectionName($0) }
        guard !sources.isEmpty else { return [] }
        return candidate.stateFields
            .filter { isSelectionName($0.name) }
            .map { selection in
                ViewModelInteractionCandidate(
                    family: .referentialIntegrity,
                    typeName: candidate.typeName,
                    subjects: [selection.name],
                    rationale: "'\(selection.name)' should reference an element of a sibling "
                        + "collection (\(sources.joined(separator: " / "))) — or be empty/nil"
                )
            }
    }

    // MARK: - Conservation (count ↔ collection size)

    private static func conservation(_ candidate: ViewModelCandidate) -> [ViewModelInteractionCandidate] {
        let collections = candidate.stateFields.filter { isCollection($0.typeText) }.map(\.name)
        guard !collections.isEmpty else { return [] }
        return candidate.stateFields
            .filter { $0.name.lowercased().contains("count") && stripOptional($0.typeText) == "Int" }
            .map { counter in
                ViewModelInteractionCandidate(
                    family: .conservation,
                    typeName: candidate.typeName,
                    subjects: [counter.name],
                    rationale: "'\(counter.name)' should track the size of a sibling collection "
                        + "(\(collections.joined(separator: " / ")))"
                )
            }
    }

    // MARK: - Cardinality (≥2 mutually-exclusive presentation routes)

    private static func cardinality(_ candidate: ViewModelCandidate) -> [ViewModelInteractionCandidate] {
        let presentation = candidate.stateFields
            .filter { isOptional($0.typeText) && isPresentationName($0.name) }
            .map(\.name)
        guard presentation.count >= 2 else { return [] }
        return [
            ViewModelInteractionCandidate(
                family: .cardinality,
                typeName: candidate.typeName,
                subjects: presentation,
                rationale: "at most one presentation route should be active at a time "
                    + "(mutually-exclusive Optionals: \(presentation.joined(separator: ", ")))"
            )
        ]
    }

    // MARK: - Biconditional (Bool flag ⟺ Optional, shared stem)

    private static func biconditional(_ candidate: ViewModelCandidate) -> [ViewModelInteractionCandidate] {
        let optionals = candidate.stateFields.filter { isOptional($0.typeText) }
        var out: [ViewModelInteractionCandidate] = []
        for flag in candidate.stateFields where isBool(flag.typeText) {
            let stem = booleanStem(flag.name)
            guard stem.count >= 3,
                  let match = optionals.first(where: { $0.name.lowercased().contains(stem) }) else {
                continue
            }
            out.append(
                ViewModelInteractionCandidate(
                    family: .biconditional,
                    typeName: candidate.typeName,
                    subjects: [flag.name, match.name],
                    rationale: "'\(flag.name)' should hold iff '\(match.name) != nil' "
                        + "(shared stem '\(stem)')"
                )
            )
        }
        return out
    }

    // MARK: - Field-shape helpers

    static func isOptional(_ type: String) -> Bool { type.hasSuffix("?") }

    static func isBool(_ type: String) -> Bool { stripOptional(type) == "Bool" }

    static func isCollection(_ type: String) -> Bool {
        let base = stripOptional(type)
        return base.hasPrefix("[")
            || base.contains("Set<") || base.contains("Array<")
            || base.contains("Dictionary<") || base.contains("IdentifiedArray")
    }

    static func isSelectionName(_ name: String) -> Bool {
        name.lowercased().hasPrefix("selected")
    }

    static func isPresentationName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return ["sheet", "alert", "popover", "route", "destination", "presented", "cover", "dialog"]
            .contains { lowered.contains($0) }
    }

    /// Strip a Bool's `is`/`has`/`show`/`should` prefix to its stem
    /// (`isLoading` → `loading`), lowercased; empty if nothing left.
    static func booleanStem(_ name: String) -> String {
        let lowered = name.lowercased()
        for prefix in ["isshowing", "is", "has", "show", "should", "did", "will"]
        where lowered.hasPrefix(prefix) && lowered.count > prefix.count {
            return String(lowered.dropFirst(prefix.count))
        }
        return lowered
    }

    private static func stripOptional(_ type: String) -> String {
        var trimmed = type.trimmingCharacters(in: .whitespaces)
        while trimmed.hasSuffix("?") || trimmed.hasSuffix("!") {
            trimmed = String(trimmed.dropLast())
        }
        return trimmed.trimmingCharacters(in: .whitespaces)
    }
}
