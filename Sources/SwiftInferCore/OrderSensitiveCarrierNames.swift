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
/// **No longer the primary detector, and no longer redundant either.**
/// `OrderedCarrierDiscriminator.isOrderSensitive` reads the carrier's
/// conformances and is consulted first; this list is the fallback for carriers it
/// cannot see. That sounds like dead weight and is not, for a reason worth
/// stating because it was measured wrong once:
///
/// The structural rule needs a **conformance record** for the carrier, and
/// `ProtocolCoverageMap`'s curated stdlib bake-in contains *no* collection
/// refinements — no `Array: RandomAccessCollection`, nothing. So in a corpus that
/// does not itself contain the standard library, which is to say **every
/// application corpus**, the structural rule abstains on `Array` and this list is
/// the only thing standing between a user-written `extension Array { func union }`
/// and a false commutativity law. Verified by removing `"Array"` from the set and
/// watching the suggestion reappear on exactly such a corpus.
///
/// The survey that reported the two rules agreeing everywhere was run over
/// *library* corpora, where the conformances are declared in the tree being
/// scanned. That agreement measured the easy case.
///
/// **`OrderedDictionary` was removed 2026-08-01**, on the repo owner's call. It was
/// the one entry the structural rule can never replace even with perfect
/// conformance data — it conforms to `Sequence` and to nothing that marks position
/// as value-determined — so what the removal drops is a guard against a
/// user-written order-preserving `union` on it. Nothing in any surveyed corpus
/// declares one. Recorded rather than silently applied, so restoring it is a
/// one-line change with the reasoning attached.
public enum OrderSensitiveCarrierNames {

    /// Ordered / sequence collections whose `==` compares element order.
    /// `Array` / `ContiguousArray` / `ArraySlice` carry no `union` in stdlib,
    /// but a user-defined order-preserving `union` on them breaks the same
    /// way, so they are guarded too — and in an application corpus this list is
    /// the *only* guard, since the standard library's conformances are not in the
    /// tree being scanned. See the type doc.
    public static let names: Set<String> = [
        "OrderedSet",
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
