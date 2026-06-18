import Foundation
import SwiftInferCore

/// PROTOTYPE — resolves a *verifiable* referential-integrity pairing on a
/// view model: a `selected*` State field whose elements are drawn from a
/// sibling collection by VALUE (the selection's element type matches the
/// collection's element type). Emits the invariant predicate the refint
/// verifier checks after every action.
///
/// **Verifiable shape (this slice):** value membership —
///   - `selected: Set<T>` ⊆ `items: [T]` / `Set<T>`
///     → `selected.isSubset(of: Set(items))`
///   - `selected: T?` ∈ `items` (or nil)
///     → `selected == nil || Set(items).contains(selected!)`
///
/// **Gated (deferred):** keyed selection where the selection element type
/// differs from the collection element type (`selectedID: UUID?` over
/// `items: [Item]` referenced by `\.id`). That needs `Identifiable` + the
/// key path — the MVVM analog of the reducer refint `Identifiable` gate.
/// `resolve` returns `nil`, and verify skips the candidate.
public enum ViewModelRefintResolver {

    public struct Resolved: Equatable {
        /// The invariant predicate over a `probe` instance (e.g.
        /// `probe.selected.isSubset(of: Set(probe.items))`).
        public let predicate: String
        public let selectionField: String
        public let collectionField: String
    }

    enum CollectionShape: Equatable { case array, set }

    /// `identifiable` (optional) enables the **keyed** form — a scalar-key
    /// selection (`selectedID: UUID?` / `Set<UUID>`) over a collection of
    /// `Identifiable` elements referenced by `\.id`. It's gated exactly like
    /// the reducer refint `Identifiable` gate (cycle 139): keyed pairing
    /// fires only against a collection whose element classifies
    /// `.identifiable`. Pass `nil` for value-membership only.
    public static func resolve(
        _ candidate: ViewModelCandidate,
        identifiable: IdentifiableResolver? = nil
    ) -> Resolved? {
        let collections = candidate.stateFields.compactMap { field -> (String, String)? in
            guard !isSelectionName(field.name),
                  let element = collectionElement(of: field.typeText)?.1 else {
                return nil
            }
            return (field.name, element)
        }

        // Value-membership first (selection element type == collection element).
        for selection in candidate.stateFields where isSelectionName(selection.name) {
            if let resolved = resolveSetSelection(selection, collections: collections) {
                return resolved
            }
            if let resolved = resolveOptionalSelection(selection, collections: collections) {
                return resolved
            }
        }

        // Keyed (Identifiable) fallback.
        guard let identifiable else { return nil }
        for selection in candidate.stateFields where isSelectionName(selection.name) {
            if let resolved = resolveKeyed(selection, candidate: candidate, identifiable: identifiable) {
                return resolved
            }
        }
        return nil
    }

    /// Scalar key types a keyed selection (`selectedID`) plausibly indexes
    /// a collection by — matched against the selection's element type.
    static let keyLikeTypes: Set<String> = ["UUID", "Int", "String", "Int64", "Int32"]

    /// Keyed refint: a scalar-key selection over an `Identifiable`-element
    /// collection, referenced by `\.id`. The selection's key type must be
    /// scalar (`keyLikeTypes`) and the paired collection's element must
    /// classify `.identifiable`.
    private static func resolveKeyed(
        _ selection: ViewModelStateField,
        candidate: ViewModelCandidate,
        identifiable: IdentifiableResolver
    ) -> Resolved? {
        let collections = candidate.stateFields.compactMap { field -> (String, String)? in
            guard !isSelectionName(field.name),
                  let element = collectionElement(of: field.typeText)?.1,
                  identifiable.classify(typeText: element) == .identifiable else {
                return nil
            }
            return (field.name, element)
        }
        guard let collection = collections.first else { return nil }

        // `Set<K>` selection → subset of the collection's id set.
        if case let (.set, key)? = collectionElement(of: selection.typeText), keyLikeTypes.contains(key) {
            return Resolved(
                predicate: "probe.\(selection.name).isSubset(of: Set(probe.\(collection.0).map { $0.id }))",
                selectionField: selection.name,
                collectionField: collection.0
            )
        }
        // `K?` selection → nil, or an element with a matching id exists.
        if collectionElement(of: selection.typeText) == nil,
           let key = optionalElement(of: selection.typeText), keyLikeTypes.contains(key) {
            return Resolved(
                predicate: "(probe.\(selection.name) == nil "
                    + "|| probe.\(collection.0).contains { $0.id == probe.\(selection.name)! })",
                selectionField: selection.name,
                collectionField: collection.0
            )
        }
        return nil
    }

    // MARK: - Selection shapes

    private static func resolveSetSelection(
        _ selection: ViewModelStateField,
        collections: [(String, String)]
    ) -> Resolved? {
        guard let (_, element) = collectionElement(of: selection.typeText),
              let collection = collections.first(where: { $0.1 == element }) else {
            return nil
        }
        return Resolved(
            predicate: "probe.\(selection.name).isSubset(of: Set(probe.\(collection.0)))",
            selectionField: selection.name,
            collectionField: collection.0
        )
    }

    private static func resolveOptionalSelection(
        _ selection: ViewModelStateField,
        collections: [(String, String)]
    ) -> Resolved? {
        // Only a *scalar* Optional (not an Optional collection) is a
        // single-element selection.
        guard collectionElement(of: selection.typeText) == nil,
              let element = optionalElement(of: selection.typeText),
              let collection = collections.first(where: { $0.1 == element }) else {
            return nil
        }
        return Resolved(
            predicate: "(probe.\(selection.name) == nil "
                + "|| Set(probe.\(collection.0)).contains(probe.\(selection.name)!))",
            selectionField: selection.name,
            collectionField: collection.0
        )
    }

    // MARK: - Type helpers

    static func isSelectionName(_ name: String) -> Bool {
        name.lowercased().hasPrefix("selected")
    }

    /// `[T]` / `Array<T>` / `Set<T>` → `(shape, T)`; else `nil`.
    static func collectionElement(of type: String) -> (CollectionShape, String)? {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            return (.array, inner(trimmed, dropLeading: 1, dropTrailing: 1))
        }
        if trimmed.hasPrefix("Set<"), trimmed.hasSuffix(">") {
            return (.set, inner(trimmed, dropLeading: 4, dropTrailing: 1))
        }
        if trimmed.hasPrefix("Array<"), trimmed.hasSuffix(">") {
            return (.array, inner(trimmed, dropLeading: 6, dropTrailing: 1))
        }
        return nil
    }

    static func optionalElement(of type: String) -> String? {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("?") else { return nil }
        return String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func inner(_ text: String, dropLeading: Int, dropTrailing: Int) -> String {
        String(text.dropFirst(dropLeading).dropLast(dropTrailing)).trimmingCharacters(in: .whitespaces)
    }
}
