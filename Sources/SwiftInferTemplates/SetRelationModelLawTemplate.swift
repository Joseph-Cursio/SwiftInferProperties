import Foundation
import SwiftInferCore

/// The **boolean-valued model law** — a set relation must agree with the membership
/// predicate the same carrier publishes.
///
///     if a.isDisjoint(with: b) { expect(!(a.contains(x) && b.contains(x))) }
///
/// Built from rows 6 and 7 of the swift.org `loops` answer key, the two
/// `gap-with-witness` entries `ModelLawTemplate` did not close. See
/// `SetRelationModelPairing` for why a relation cannot be stated as an equation, which
/// direction this checks, and the kit non-duplication check.
public enum SetRelationModelLawTemplate {

    public static func suggest(
        for shape: SetRelationModelPairing.SetRelationShape
    ) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: shape)
    }

    public static func makeConstraint()
        -> Constraint<SetRelationModelPairing.SetRelationShape> {
        Constraint<SetRelationModelPairing.SetRelationShape>(
            templateName: "set-relation-model-law",
            appliesTo: { _ in true },
            signals: Self.signals(for:),
            evidence: { [$0.relation.inferenceEvidence, $0.membership.inferenceEvidence] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.typeName },
            carrierType: { $0.typeName },
            caveats: Self.makeCaveats(for:),
            additionalWhySuggested: Self.makeWhySuggested(for:),
            generators: Self.makeGenerators(for:)
        )
    }

    /// 70 (Likely), or 80 (Strong) when the carrier exposes all three relations.
    ///
    /// One tier below its sibling's baseline on purpose: the equation form is a
    /// biconditional and refutable from either side, while this one checks a single
    /// implication and cannot see a wrongly-`false` predicate at all. Less law, less claim.
    static func signals(
        for shape: SetRelationModelPairing.SetRelationShape
    ) -> [Signal] {
        var signals = [
            Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated set-relation name: '\(shape.form.rawValue)' — its membership "
                    + "semantics are definitional (\(shape.form.prose)), not a convention this "
                    + "type is free to reinterpret"
            ),
            Signal(
                kind: .predicateSignature,
                weight: 30,
                detail: "Set-relation shape: (\(shape.typeName)) -> Bool, with `contains` "
                    + "supplying the characteristic function to hold the answer to"
            )
        ]
        if shape.siblingRelationCount >= 3 {
            signals.append(Signal(
                kind: .algebraicStructureCluster,
                weight: 10,
                detail: "\(shape.siblingRelationCount) curated set relations co-occur on "
                    + "\(shape.typeName) — the carrier is set-like by construction, not by one name"
            ))
        }
        return signals
    }

    static func makeWhySuggested(
        for shape: SetRelationModelPairing.SetRelationShape
    ) -> [String] {
        [
            "Abstraction function: \(shape.typeName).contains(_:) -> Bool at "
                + "\(shape.membership.location) — the "
                + "relation claims something about membership, so membership is what can check it"
        ]
    }

    static func makeCaveats(
        for shape: SetRelationModelPairing.SetRelationShape
    ) -> [String] {
        let law = shape.form.pointwiseLaw("a", "b", element: "x")
        return [
            "THE LAW IS `\(law)` — `\(shape.form.rawValue)` claims that \(shape.form.prose). "
                + "Confirm that is what this type means by the name; a type using it for a "
                + "range or prefix test does not owe this law.",
            "IT CHECKS ONE DIRECTION ONLY, AND YOU SHOULD KNOW WHICH. A wrongly-TRUE answer is "
                + "refuted by \(shape.form.refutedBy). A wrongly-FALSE answer cannot be refuted "
                + "pointwise at all — that needs an existential ('there is no such x'), which no "
                + "single trial establishes. The direction it does check is the one that fails in "
                + "practice for interval- and bitset-backed implementations.",
            "THE ELEMENT GENERATOR DECIDES WHETHER THIS LAW TESTS ANYTHING. The law is only "
                + "reachable when the guard is true AND `x` lands where the operands disagree. "
                + "Draw `x` from the SAME narrow alphabet the operands are built from, including "
                + "the boundary values — an interval's endpoints, a bitset's word seams. Drawn "
                + "widely, the guard passes, `contains` is false everywhere, and every trial is "
                + "vacuously green.",
            "The kit's `checkSetAlgebraPropertyLaws` does NOT subsume this. Its 15 laws relate "
                + "the operations to each other and mention `isSubset` / `isDisjoint` / "
                + "`isSuperset` zero times."
        ]
    }

    static func makeGenerators(
        for shape: SetRelationModelPairing.SetRelationShape
    ) -> [GeneratorRecipe] {
        [
            GeneratorRecipe(
                subject: "x",
                typeName: shape.elementTypeText,
                expression: "Gen<\(shape.elementTypeText)>.element(of: sharedAlphabet)",
                rationale: "DELIBERATELY NARROW, and doubly so here. The law is guarded — it "
                    + "only runs when `\(shape.form.rawValue)` answers true — so a wide alphabet "
                    + "loses twice: the guard rarely holds, and when it does `x` misses both "
                    + "operands. Build the operands and `x` from one small shared alphabet and "
                    + "include the boundary values, or the suite is green having checked nothing."
            )
        ]
    }

    static func makeIdentity(
        for shape: SetRelationModelPairing.SetRelationShape
    ) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: "set-relation-model-law|\(shape.typeName)|\(shape.form.rawValue)|"
                + IdempotenceTemplate.canonicalSignature(of: shape.relation)
        )
    }
}
