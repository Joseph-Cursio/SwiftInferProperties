import SwiftInferCore

/// Which type names a package declares as classes and as actors, for #669's criterion 1: a method keeps
/// state across calls on a class, and on an actor too, but a test can call an actor's method only with
/// `await`, so `UniquifierTemplate` declines those for now.
public struct UniquifierOwners: Sendable {
    /// Names declared `class`.
    public let classes: Set<String>
    /// Names declared `actor`.
    public let actors: Set<String>

    /// Reads both sets off `typeDecls`.
    public init(typeDecls: [TypeDecl]) {
        classes = Set(typeDecls.filter { $0.kind == .class }.map(\.name))
        actors = Set(typeDecls.filter { $0.kind == .actor }.map(\.name))
    }
}
