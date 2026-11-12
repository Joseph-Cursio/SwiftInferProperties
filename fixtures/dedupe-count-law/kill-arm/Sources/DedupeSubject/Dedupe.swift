// Copied verbatim from SwiftUMLStudio `9ad7631` (identical at `e36da59`) for #671's kill arm
// (`docs/plans/dedupe-count-law-census-scope.md` §1.1). `ERCardinality` and `ERRelationship` from
// `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Model/ERModel.swift`; `dedupe` from
// `Parsing/CoreDataModelExtractor.swift:154`. The `// L16x` comments are the mutation anchors; nothing else is changed.

/// Cardinality of an endpoint of an ER relationship.
public enum ERCardinality: String, Sendable, Hashable {
    /// Optional to-one (e.g., `var author: Author?`).
    case zeroOrOne
    /// Required to-one (e.g., `var author: Author`).
    case exactlyOne
    /// Optional to-many (e.g., `var books: [Book]` — empty collection is valid).
    case zeroOrMany
    /// Required to-many (rare in SwiftData; reserved for emitters that want to
    /// distinguish "must have at least one" from zero-or-many).
    case oneOrMany
}

/// A relationship edge between two ER entities.
///
/// Both endpoints carry a cardinality, so the emitter can render crow's-foot
/// style connectors (`||--o{`, `}o--||`, etc.) without re-deriving them.
public struct ERRelationship: Sendable, Hashable {
    public let from: String
    public let toEntity: String
    public let fromCardinality: ERCardinality
    public let toCardinality: ERCardinality
    public let label: String
    public let inverseLabel: String?

    public init(
        from: String,
        toEntity: String,
        fromCardinality: ERCardinality,
        toCardinality: ERCardinality,
        label: String,
        inverseLabel: String? = nil
    ) {
        self.from = from
        self.toEntity = toEntity
        self.fromCardinality = fromCardinality
        self.toCardinality = toCardinality
        self.label = label
        self.inverseLabel = inverseLabel
    }
}

public enum CoreDataModelExtractor {
    /// Drops a relationship whose inverse already appears in the list, so each
    /// edge is emitted once rather than twice (Core Data declares both sides).
    static func dedupe(relationships: [ERRelationship]) -> [ERRelationship] {
        var seen: Set<String> = []
        var result: [ERRelationship] = []
        for relationship in relationships {
            let endpoints = [relationship.from, relationship.toEntity].sorted()
            let labels = [relationship.label, relationship.inverseLabel ?? ""].sorted()
            let key = "\(endpoints[0])|\(endpoints[1])|\(labels[0])|\(labels[1])"
            if !seen.contains(key) { // L161
                seen.insert(key) // L162
                result.append(relationship) // L163
            }
        }
        return result
    }
}
