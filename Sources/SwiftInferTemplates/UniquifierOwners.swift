import SwiftInferCore

/// Which type names a package declares as classes and as actors, for #669's criterion 1: a method keeps
/// state across calls on a class, and on an actor too, but a test can call an actor's method only with
/// `await`, so `UniquifierTemplate` declines those for now.
public struct UniquifierOwners: Sendable {
    /// Names declared `class`.
    public let classes: Set<String>
    /// Names declared `actor`.
    public let actors: Set<String>
    /// For each type with one, its first initializer whose every parameter is a collection of `String`.
    public let reservations: [String: UniquifierReservation]

    /// Reads all three off `typeDecls`.
    public init(typeDecls: [TypeDecl]) {
        classes = Set(typeDecls.filter { $0.kind == .class }.map(\.name))
        actors = Set(typeDecls.filter { $0.kind == .actor }.map(\.name))
        var found: [String: UniquifierReservation] = [:]
        for decl in typeDecls where found[decl.name] == nil {
            let reserving = decl.initializers.first { initializer in
                !initializer.parameters.isEmpty && initializer.parameters.allSatisfy { Self.isNames($0.typeName) }
            }
            if let reserving {
                found[decl.name] = UniquifierReservation(
                    labels: reserving.parameters.map(\.label),
                    types: reserving.parameters.map(\.typeName)
                )
            }
        }
        reservations = found
    }

    /// `[String]`, `Array<String>` or `Set<String>`.
    static func isNames(_ type: String) -> Bool {
        ["[String]", "Array<String>", "Set<String>"].contains(type.filter { !$0.isWhitespace })
    }
}
