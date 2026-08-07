import SwiftInferCore

/// Op-class → `KnownProperty` candidate tables for the commutativity veto.
///
/// **Extracted 2026-08-02**, when adding the `intersection` and `symmetricDifference`
/// arms took `CommutativityTemplate.swift` past the 400-line cap. The table is the
/// natural seam: it is the only part of the template that is a claim about
/// *PropertyLawKit* rather than about the candidate function, and it is shared —
/// `AssociativityTemplate` reuses the op-class shape.
///
/// **What the extraction is really for.** Three of these arms did not exist until a
/// law-by-law audit of the kit found `discover` double-reporting laws
/// `checkSetAlgebraPropertyLaws` already runs. A table that falls through to `[]` is
/// indistinguishable, at the call site, from a table that has considered the verb and
/// decided the kit does not cover it. Keeping it in one small file with this note is
/// the cheapest guard against the next verb being added to `setCombinationVerbs`
/// without a matching arm here. See `docs/measurements/protocol-coverage-law-drift.md`.
extension CommutativityTemplate {

    /// V1.5.2 — op-class → KnownProperty candidate set for the
    /// commutativity veto. `static internal` so AssociativityTemplate
    /// can reuse the same op-class shape (commutativity / associativity
    /// share the curated verb list per the AssociativityTemplate type
    /// doc).
    static func commutativityCoverageCandidates(forOp opName: String) -> [KnownProperty] {
        switch opName {
        case "+":
            return [.additiveCommutative]

        case "*":
            return [.multiplicativeCommutative]

        case "union", "formUnion":
            return [.setUnionCommutative]

        // 2026-08-02 — these two fell through to `default` while
        // `setCombinationVerbs` proposed commutativity on them, so the kit's
        // `intersectionCommutativity` / `symmetricDifferenceCommutativity` were
        // double-reported. Measured on a two-carrier probe: both surfaced on the
        // concrete AND the `Self` spelling. `docs/measurements/protocol-coverage-law-drift.md` §3.
        case "intersection", "formIntersection", "intersect":
            return [.setIntersectionCommutative]

        case "symmetricDifference", "formSymmetricDifference":
            return [.setSymmetricDifferenceCommutative]

        default:
            return []
        }
    }
}
