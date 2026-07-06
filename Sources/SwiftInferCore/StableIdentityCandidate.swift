/// A `Hashable class` the engine recognizes as an **identity-stability**
/// verification candidate (pbt-book Ch. 9 §9.3.3): mutating an instance must not
/// change its `==` / `hashValue`, or it corrupts any `Set` / `Dictionary` that
/// holds it. Emitted by `StableIdentityDiscoverer`.
///
/// The signal is deliberately broad — a `Hashable` class with a mutation surface
/// — and the *verifier decides*: if driving the mutations leaves the hash /
/// equality unchanged it is safe; if a mutation disturbs them the class is unsafe
/// as a key. Only mutable `Hashable` classes are surfaced (an all-immutable
/// identity can't drift).
public struct StableIdentityCandidate: Sendable, Equatable {

    public let typeName: String
    public let location: SourceLocation

    /// Instance methods that mutate the class — driven to probe whether any of
    /// them disturbs the identity. (Reuses `MutationMethod`.)
    public let mutationSurface: [MutationMethod]

    public init(typeName: String, location: SourceLocation, mutationSurface: [MutationMethod]) {
        self.typeName = typeName
        self.location = location
        self.mutationSurface = mutationSurface
    }
}
