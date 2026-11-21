/// How a recognised dedupe's body keeps one element per key: #671's body gate, as
/// `DedupeBodyReader` reads it (`docs/plans/dedupe-count-law-census-scope.md` §2.4).
///
/// Carried on the suggestion as `TemplateMatch.dedupeCount`, so the stub writer emits #671's two
/// count laws without reading the body again:
///
/// - **C1** `value.allSatisfy { f([$0]).count == 1 }`: a singleton survives;
/// - **C2** `f(value + value).count == f(value).count`: a duplicate of everything adds nothing.
///
/// Both compare counts, so they compile for any element type and need neither `Hashable` nor a
/// collision-biased generator: C2 builds its own duplicates. Idempotence holds of the identity and
/// of `[]`, the two simplest dedupe bugs; C2 fails the first and C1 the second
/// (`fixtures/dedupe-count-law/kill-arm/`, measured).
public struct DedupeBody: Sendable, Equatable, Codable {

    /// The two body shapes the gate admits.
    public enum Route: String, Sendable, Codable {
        /// A `Set` local, and elements reach the result only through a successful insert.
        case set
        /// A dictionary local written `d[k] = x`, every skip guarded by a read of `d[k]`, and a
        /// return of `Array(d.values)`.
        case dictionary
    }

    public let route: Route

    public init(route: Route) {
        self.route = route
    }

    /// Whether the result keeps each key's first element in input order.
    ///
    /// True on the Set route only. The dictionary route returns `Array(d.values)`, in hash order,
    /// so `f(value + value) == f(value)` may be false of correct code there: two dictionaries with
    /// the same entries need not list them in the same order. The count form holds on both routes.
    public var keepsFirst: Bool { route == .set }
}
