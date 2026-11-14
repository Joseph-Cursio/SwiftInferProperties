/// How an argument-free member is read off a value: `value.count` or `value.count()`.
///
/// Persisted as `SemanticIndexEntry.secondaryMemberShape` (#701). **An enum rather than a
/// `Bool?`** because the column has three states and each means something different: a property,
/// a method, and `nil` — *not recorded*, on an entry indexed before the column existed or for a
/// template that does not need it. A `Bool?` spells the third state as the absence of the first
/// two, which is how a reader comes to treat `nil` as `false` and guess the method spelling.
///
/// **Why it must be recorded at all.** `Evidence.displayName` reads `count()` for a computed
/// property and a nullary method alike, and the two have no shared spelling: `value.count()` on a
/// property and `value.count` on a method both fail to compile.
public enum MemberAccessShape: String, Codable, Sendable, Equatable, CaseIterable {
    /// `value.count` — a read-only computed property.
    case computedProperty = "computed-property"
    /// `value.count()` — an instance method that takes no arguments.
    case nullaryMethod = "nullary-method"

    /// The shape an `Evidence` / `FunctionSummary` flag describes.
    public init(isComputedProperty: Bool) {
        self = isComputedProperty ? .computedProperty : .nullaryMethod
    }

    /// `name` as written after `value.`: `count` or `count()`.
    public func spelling(of bareName: String) -> String {
        switch self {
        case .computedProperty: bareName
        case .nullaryMethod: "\(bareName)()"
        }
    }
}
