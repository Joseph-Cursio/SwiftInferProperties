import Foundation

/// V2.0 M4.B — one detected Conservation witness inside a reducer's
/// State struct: a stored aggregate property paired with a collection
/// property whose count (or eventual sum) the aggregate should mirror.
///
/// **What M4.B detects (and what it doesn't).** M4.B ships the
/// *count-shaped* variant only:
///
///   - Aggregate name matches a count pattern (case-insensitive):
///     `count`, `numXxx`, `<X>Count`.
///   - Aggregate type is an integer (`Int`, `UInt`, `Int32`, etc.).
///   - Collection is an array `[T]` (`Set` / `Dictionary` deferred).
///   - Predicate: `state.<aggregate> == state.<collection>.count`.
///
/// Sum-shaped conservation invariants (`total: Decimal` paired with
/// `items: [LineItem]` summing `\.price`) need to walk into the
/// element type to find which numeric field to sum on. That widens
/// the surface significantly — deferred to a later M4.B refinement
/// or M4 follow-on.
///
/// Floating-point aggregate types (`Double`, `Float`) are excluded
/// at detection time per PRD §5.2's counter-signal: IEEE-754
/// round-off makes exact equality fragile. The §5 emitted-property
/// example mentions an approximate-equality variant; M4.B defers it.
public struct ConservationWitness: Sendable, Equatable, Codable {

    /// Name of the stored aggregate property, e.g. `"count"` /
    /// `"itemCount"` / `"numEntries"`.
    public let aggregatePropertyName: String

    /// Type-annotation text of the aggregate property, e.g. `"Int"`
    /// / `"UInt"`. Stored verbatim from source so the rendered
    /// suggestion preserves it.
    public let aggregateTypeName: String

    /// Name of the contributing collection property, e.g. `"items"`
    /// / `"entries"`.
    public let collectionPropertyName: String

    /// Element type of the collection, extracted from `[T]`. For
    /// `items: [LineItem]`, this is `"LineItem"`.
    public let elementTypeName: String

    public init(
        aggregatePropertyName: String,
        aggregateTypeName: String,
        collectionPropertyName: String,
        elementTypeName: String
    ) {
        self.aggregatePropertyName = aggregatePropertyName
        self.aggregateTypeName = aggregateTypeName
        self.collectionPropertyName = collectionPropertyName
        self.elementTypeName = elementTypeName
    }
}
