import Foundation

/// swift-algorithms (`apple/swift-algorithms`) laws — properties of the package's
/// lazy transformations, stated against the array model. `uniqued` is idempotent;
/// `chunks` then flatten is the identity; `min(count:)` agrees with the sorted
/// prefix. Carry `imports: ["Algorithms"]` → the package verify path.
extension StandardLibraryProperties {

    static let algorithmsLaws: [KnownProperty] = [
        law(
            "Algorithms.uniqued", "idempotent under uniqued",
            "Array(a.uniqued().uniqued()) == Array(a.uniqued())",
            "let a = randArr(); return Array(a.uniqued().uniqued()) == Array(a.uniqued())",
            template: "idempotence", imports: ["Algorithms"]
        ),
        law(
            "Algorithms.chunks", "chunk then flatten is the identity",
            "Array(a.chunks(ofCount: 3).joined()) == a",
            "let a = randArr(); return Array(a.chunks(ofCount: 3).joined()) == a",
            imports: ["Algorithms"]
        ),
        law(
            "Algorithms.min", "min(count:) agrees with the sorted prefix",
            "Array(a.min(count: k)) == Array(a.sorted().prefix(k))",
            "let a = randArr(); let k = Swift.min(3, a.count); "
                + "return Array(a.min(count: k)) == Array(a.sorted().prefix(k))",
            imports: ["Algorithms"]
        )
    ]
}
