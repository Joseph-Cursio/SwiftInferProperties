/// V1.14.1 — canonical home for the curated `SetAlgebra` binary-op
/// function-name set used by `InversePairTemplate`'s SetAlgebra-shape
/// veto helper (and any future template that detects this shape).
///
/// **Canonical from cycle 1.** Lives in `SwiftInferCore` from V1.14.1
/// without a per-template intermediate, applying the v1.13 hoist
/// lesson preemptively: shared template-agnostic curated sets live
/// in core's namespace from day one rather than waiting for a
/// third-consumer trigger to hoist.
///
/// Companion to `DirectionLabels.curated` (V1.13.1) — the two are
/// the canonical homes for cycle-N curated data sets used across
/// templates. Both factored as `public enum <Name> { public static
/// let <subset>: Set<String> }` for the same reasons (Swift namespacing
/// for static lets, `CaseIterable`-style closed-set discoverability).
public enum SetAlgebraShape {

    /// 4-element curated set of `(Self) -> Self`-returning binary-op
    /// method names from Swift's `SetAlgebra` protocol surface. Used
    /// by `InversePairTemplate.setAlgebraShapeVeto(for:)` to suppress
    /// inverse-pair claims whose forward + reverse function names are
    /// both drawn from this set — these are SetAlgebra *operations*,
    /// not *inverses*.
    ///
    /// Set chosen to match `(Self) -> Self`-shaped methods only:
    /// - `union(_:) -> Self`
    /// - `intersection(_:) -> Self`
    /// - `symmetricDifference(_:) -> Self`
    /// - `subtracting(_:) -> Self`
    ///
    /// Deliberately excludes the form-mutating siblings (`formUnion`,
    /// `formIntersection`, etc.) — they're Void-returning and don't
    /// match `(Self) -> Self` shape, so they don't enter
    /// `FunctionPairing`'s candidate generation in the first place.
    /// Predicate methods (`isSubset`, `isSuperset`, `isDisjoint`, etc.)
    /// return `Bool` and are similarly excluded by structural
    /// construction.
    ///
    /// **Cycle-6 / cycle-9 motivation.** Cycle-6's single-runner triage
    /// surfaced 5 inverse-pair rejections; 3 of 5 (#45-#47) were
    /// `intersection ↔ subtracting`-style on `OrderedSet`. Cycle-9's
    /// post-direction-counter snapshot expanded that to 6 OC inverse-
    /// pair survivors via cross-file pairing across `OrderedSet+Partial
    /// SetAlgebra intersection.swift` × `OrderedSet+Partial SetAlgebra
    /// subtracting.swift` × `OrderedSet+UnorderedView.swift`. V1.14.1
    /// closes that pattern.
    public static let binaryOps: Set<String> = [
        "union",
        "intersection",
        "symmetricDifference",
        "subtracting"
    ]
}
