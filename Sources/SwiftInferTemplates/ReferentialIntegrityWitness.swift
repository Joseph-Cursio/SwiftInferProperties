import Foundation

/// V2.0 M6 — one detected Referential Integrity witness inside a
/// reducer's State struct: a "selected ID" Optional field paired
/// with a collection whose elements the selection is supposed to
/// reference (PRD §5.5).
///
/// **What M6 detects.** The simplest shape — `selectedX: T?` paired
/// with `xs: [U]` in the same State struct. The detector pairs by
/// Cartesian product (every selected-optional × every array
/// collection in the State) and lets calibration narrow.
///
/// **What M6 doesn't yet detect.**
///
///   - **Type-relationship resolution.** PRD §5.5 names the canonical
///     shape as `selectedX: T.ID?` paired with `xs: [T]` where
///     `T: Identifiable`. v0.0 detection is name-only — every
///     "selected" Optional pairs with every Array. The synthesized
///     verifier uses `$0.id == state.<selectedField>`, which fails
///     to compile when the element type isn't `Identifiable` (or
///     the IDs don't compare); that surfaces as
///     `.architecturalCoveragePending` per M3.E.3's outcome
///     mapping. The why-might-be-wrong block names this as a
///     known caveat.
///   - **Route / NavigationPath / Destination enums.** PRD §5.5's
///     second witness shape. Deferred — they require enum-case-
///     payload type analysis beyond what state-field scanning
///     covers.
///   - **Reducer-body strengthening signal** (PRD §5.5 third
///     witness: `.select(_:)` writes to ID + `.delete(_:)` clears
///     collection without clearing selection). Deferred to the
///     same body-walking surface that M5's strengthening signal
///     awaits.
public struct ReferentialIntegrityWitness: Sendable, Equatable, Codable {

    /// Name of the "selected" Optional property, e.g.
    /// `"selectedMessageID"` / `"selectedItem"`.
    public let selectedPropertyName: String

    /// Type-annotation text of the selected property, with the
    /// trailing `?` retained. E.g. `"UUID?"` / `"Message.ID?"` /
    /// `"Optional<UUID>"`.
    public let selectedTypeName: String

    /// Name of the contributing collection property, e.g.
    /// `"messages"` / `"items"`.
    public let collectionPropertyName: String

    /// Element type of the collection extracted from `[T]`. The
    /// emitted predicate uses `$0.id` against this element type —
    /// the user's `T` must conform to `Identifiable` for the
    /// synthesized verifier to compile.
    public let elementTypeName: String

    public init(
        selectedPropertyName: String,
        selectedTypeName: String,
        collectionPropertyName: String,
        elementTypeName: String
    ) {
        self.selectedPropertyName = selectedPropertyName
        self.selectedTypeName = selectedTypeName
        self.collectionPropertyName = collectionPropertyName
        self.elementTypeName = elementTypeName
    }
}
