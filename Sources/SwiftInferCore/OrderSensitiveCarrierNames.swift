/// B29 — curated type names whose `==` is **element-order-sensitive**: two
/// values holding the same members in a different order compare *unequal*.
///
/// On these carriers the set-combination operations (`union`, `intersection`,
/// …) are order-preserving, so their **commutativity** semilattice law does
/// NOT hold under `==`: `a.union(b)` and `b.union(a)` contain the same members
/// but in a different order, and therefore compare unequal. The law holds only
/// under an order-*insensitive* comparison — OrderedCollections spells that
/// `isEqualSet`. `CommutativityTemplate` vetoes a set-verb commutativity
/// suggestion when the carrier appears here.
///
/// **Pre-SemanticIndex approximation.** A hand-curated denylist stands in for
/// structural detection of an order-sensitive `==` (which the textual model
/// cannot see), mirroring `FloatingPointStorageNames`. The reach gates that
/// made `OrderedSet.union` discoverable reopened exactly the "NOT
/// order-commutative" caveat the calibration had hand-encoded; this list is
/// where that knowledge lives on the discovery side. New order-sensitive
/// collections are not guarded until added here.
public enum OrderSensitiveCarrierNames {

    /// Ordered / sequence collections whose `==` compares element order.
    /// `Array` / `ContiguousArray` / `ArraySlice` carry no `union` in stdlib,
    /// but a user-defined order-preserving `union` on them breaks the same
    /// way, so they are guarded too.
    public static let names: Set<String> = [
        "OrderedSet",
        "OrderedDictionary",
        "Deque",
        "Array",
        "ContiguousArray",
        "ArraySlice"
    ]

    /// Whether `typeText` names an order-sensitive carrier. Generic parameters
    /// are stripped textually before lookup (`OrderedSet<Int>` → `OrderedSet`).
    public static func contains(_ typeText: String) -> Bool {
        names.contains(strippingGenericParameters(typeText))
    }

    /// Strip a single generic-parameter list from a textual type name:
    /// `OrderedSet<Int>` → `OrderedSet`, `Foo` → `Foo`. Pure textual operation,
    /// matching `FloatingPointStorageNames`' limitation (no nested generics or
    /// type aliases).
    public static func strippingGenericParameters(_ name: String) -> String {
        guard let openAngle = name.firstIndex(of: "<") else { return name }
        return String(name[..<openAngle])
    }
}
