import Foundation
import SwiftInferCore

/// The **model law**: an operation must agree with the semantics its name claims, checked
/// through an abstraction function rather than against the type's own algebra.
///
/// ## Two independent lines of evidence asked for this template
///
/// **1 — three real bugs that pass every law we had.** `fixtures/equatable-signal/README.md`
/// measured `Equatable` as a conformance-keyed signal across swift-numerics and
/// swift-collections and concluded the opposite of what it set out to test: conformance does
/// not predict refutability, and when `==` is a *projection* of the stored fields it remains
/// an equivalence relation however wrong it is. Three real projection bugs — `OrderedSet`
/// order, `BitArray` padding, `Deque` head rotation — pass **4 of 4** Equatable laws and die
/// at trial ≤3 against a model. The recorded recommendation was *"propose the model law, not
/// the Equatable laws, for projections."* Nothing implemented it.
///
/// **2 — swift.org writes it by hand, five times, for one type.** The `loops` population
/// (`docs/swiftorg-property-test-study-findings.md` §1.25) found `RangeSet` checking `union`,
/// `intersection`, `symmetricDifference`, `isDisjoint` and `isSubset` against `Set<Int>` as
/// reference semantics, with a hand-written `unionViaSet` per operation. Those five were
/// `gap-with-witness` — the largest single cluster in a population that scored **33%**
/// covered against `check-battery`'s 100%.
///
/// Two lines of evidence, arrived at from opposite directions, naming the same missing shape.
///
/// ## What it states
///
///     (a.union(b)).contains(x) == (a.contains(x) || b.contains(x))
///
/// See `ModelLawPairing` for why the abstraction function is `contains` rather than a
/// conversion to `Set` (the motivating type conforms to neither `SetAlgebra` nor `Sequence`,
/// so there is no conversion to be had), and for why this does not double-report against the
/// kit's 15 `SetAlgebra` laws (they relate the operations to each other and mention `contains`
/// zero times).
///
/// ## The law it rejects
///
/// A range-backed `union` that fails to merge the seam `[1,3) ∪ [3,5)` into `[1,5)`. That
/// implementation is commutative, idempotent, absorptive and De Morgan-compliant — it passes
/// all 15 kit laws — and it answers `contains(3)` wrongly. Seam handling is where interval
/// and bitset implementations actually break, and the algebra cannot see it.
public enum ModelLawTemplate {

    public static func suggest(for shape: ModelLawPairing.MembershipModelShape) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: shape)
    }

    public static func makeConstraint() -> Constraint<ModelLawPairing.MembershipModelShape> {
        Constraint<ModelLawPairing.MembershipModelShape>(
            templateName: "model-law",
            appliesTo: { _ in true },
            signals: Self.signals(for:),
            evidence: { [$0.operation.inferenceEvidence, $0.membership.inferenceEvidence] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.typeName },
            carrierType: { $0.typeName },
            caveats: Self.makeCaveats(for:),
            additionalWhySuggested: Self.makeWhySuggested(for:),
            generators: Self.makeGenerators(for:)
        )
    }

    static func signals(for shape: ModelLawPairing.MembershipModelShape) -> [Signal] {
        var signals = [
            Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated set-operation name: '\(shape.form.rawValue)' — its membership "
                    + "semantics are definitional (\(shape.form.membershipProse)), not a convention "
                    + "this type is free to reinterpret"
            ),
            Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Set-operation shape: (\(shape.typeName)) -> \(shape.typeName), with "
                    + "`contains` supplying the characteristic function to state it against"
            )
        ]
        // Three or more curated operations on one carrier is not a coincidence. A lone
        // `union` might be a merge or an append; `union` + `intersection` +
        // `symmetricDifference` is a Boolean algebra announcing itself.
        if shape.siblingOperationCount >= 3 {
            signals.append(Signal(
                kind: .algebraicStructureCluster,
                weight: 10,
                detail: "\(shape.siblingOperationCount) curated set operations co-occur on "
                    + "\(shape.typeName) — the carrier is set-like by construction, not by one name"
            ))
        }
        return signals
    }

    static func makeWhySuggested(for shape: ModelLawPairing.MembershipModelShape) -> [String] {
        [
            "Abstraction function: \(shape.typeName).contains(_:) -> Bool at "
                + "\(shape.membership.location.file):\(shape.membership.location.line) — a set IS "
                + "its characteristic function, so no conversion to `Set` is needed to state the law"
        ]
    }

    /// The law, spelled for the reader, plus the two ways it goes wrong.
    static func makeCaveats(for shape: ModelLawPairing.MembershipModelShape) -> [String] {
        let law = "(a.\(shape.form.rawValue)(b)).contains(x) == ("
            + shape.form.membershipExpression("a", "b", element: "x") + ")"
        return [
            "THE LAW IS `\(law)` — the result contains exactly the elements "
                + "\(shape.form.membershipProse). Confirm that is what this type means by "
                + "'\(shape.form.rawValue)'. A type that merges, de-duplicates or clamps on "
                + "combine does not owe this law, and a name collision is the way it goes wrong.",
            "THE ELEMENT GENERATOR DECIDES WHETHER THIS LAW TESTS ANYTHING. `x` drawn from a wide "
                + "domain misses both operands, `contains` is false on both sides, and the law "
                + "passes vacuously at every trial — a green run that checked nothing. Draw `x` "
                + "from the SAME narrow alphabet the operands are built from, and include the "
                + "boundary values (an interval's endpoints, a bitset's word seams). This is the "
                + "collision-dependence trap that reported `bothPass` for a commutativity law "
                + "known to be false until the alphabet was narrowed.",
            "The kit's `checkSetAlgebraPropertyLaws` does NOT subsume this. Its 15 laws relate the "
                + "operations to each other and never mention `contains`, so an implementation "
                + "wrong at a seam — `[1,3) ∪ [3,5)` not merging to `[1,5)` — passes all 15 and "
                + "fails this one at `x == 3`."
        ]
    }

    /// The element generator, with the narrowing rationale attached where a reader will see it.
    ///
    /// `GeneratorRecipe.rationale` exists for exactly this failure mode: *"a reader who does not
    /// understand why the alphabet is small will widen it back on the first cleanup pass, and
    /// the law will go quiet without anyone noticing it stopped testing anything."*
    static func makeGenerators(
        for shape: ModelLawPairing.MembershipModelShape
    ) -> [GeneratorRecipe] {
        [
            GeneratorRecipe(
                subject: "x",
                typeName: shape.elementTypeText,
                expression: "Gen<\(shape.elementTypeText)>.element(of: sharedAlphabet)",
                rationale: "DELIBERATELY NARROW. The law is only refutable where the operands "
                    + "disagree, so `x` must land INSIDE them often. Draw the operands and `x` "
                    + "from one small shared alphabet — widen it and every trial passes "
                    + "vacuously with `contains` false on both sides."
            )
        ]
    }

    static func makeIdentity(
        for shape: ModelLawPairing.MembershipModelShape
    ) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: "model-law|\(shape.typeName)|\(shape.form.rawValue)|"
                + IdempotenceTemplate.canonicalSignature(of: shape.operation)
        )
    }
}
