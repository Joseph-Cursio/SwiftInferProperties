import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The **boolean-valued model law** — `if a.isDisjoint(with: b) { !(a.contains(x) && b.contains(x)) }`.
///
/// Built from rows 6 and 7 of `fixtures/swiftorg-study/loops-answer-key.json`, the two
/// `gap-with-witness` entries `ModelLawTemplate` left open. Findings §1.25 recorded that
/// *"the five swift.org `RangeSet` witnesses are now covered"*; measured 2026-08-01 it
/// covered **three** — `isDisjoint` and `isSubset` are boolean-valued and were never in
/// `SetOperation`.
@Suite("Set-relation model law — holding a relation to the carrier's own membership")
struct SetRelationModelLawTests {

    private static let loc = SourceLocation(file: "RangeSet.swift", line: 10, column: 1)

    private func member(
        _ name: String,
        param: String,
        returns: String?,
        label: String? = nil,
        on carrier: String = "RangeSet",
        isMutating: Bool = false,
        isStatic: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: label, internalName: "other", typeText: param, isInout: false)
            ],
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: isMutating,
            isStatic: isStatic,
            location: Self.loc,
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    /// A `RangeSet`-shaped carrier: an element predicate plus the three relations.
    private func rangeSetLike() -> [FunctionSummary] {
        [
            member("contains", param: "Bound", returns: "Bool"),
            member("isDisjoint", param: "RangeSet<Bound>", returns: "Bool", label: "with"),
            member("isSubset", param: "RangeSet<Bound>", returns: "Bool", label: "of"),
            member("isSuperset", param: "RangeSet<Bound>", returns: "Bool", label: "of")
        ]
    }

    // MARK: - The witnesses

    @Test("Fires on all three relations, and the cluster bonus reaches Strong")
    func firesOnTheWitnesses() {
        let shapes = SetRelationModelPairing.candidates(in: rangeSetLike())
        #expect(shapes.count == 3)
        #expect(Set(shapes.map(\.form.rawValue)) == ["isDisjoint", "isSubset", "isSuperset"])
        let suggestion = shapes.first.flatMap(SetRelationModelLawTemplate.suggest(for:))
        #expect(suggestion?.templateName == "set-relation-model-law")
        #expect(suggestion?.score.total == 80)
        #expect(suggestion?.score.tier == .strong)
    }

    /// A lone relation might be a prefix or range test rather than set membership, so it
    /// loses the cluster bonus — the same structure the sibling template uses.
    @Test("A lone relation is Likely, not Strong")
    func loneRelationIsLikely() {
        let shapes = SetRelationModelPairing.candidates(in: [
            member("contains", param: "Bound", returns: "Bool"),
            member("isSubset", param: "RangeSet<Bound>", returns: "Bool", label: "of")
        ])
        let suggestion = shapes.first.flatMap(SetRelationModelLawTemplate.suggest(for:))
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    // MARK: - What it declines

    /// **The strict variants are deliberately absent.** `isStrictSubset` differs from
    /// `isSubset` only in requiring properness, and properness is an existential —
    /// pointwise the two produce an identical law. Emitting them would add rows that
    /// cannot test the thing their name is about.
    @Test("Strict variants are not proposed")
    func strictVariantsDeclined() {
        let shapes = SetRelationModelPairing.candidates(in: [
            member("contains", param: "Bound", returns: "Bool"),
            member("isStrictSubset", param: "RangeSet<Bound>", returns: "Bool", label: "of"),
            member("isStrictSuperset", param: "RangeSet<Bound>", returns: "Bool", label: "of")
        ])
        #expect(shapes.isEmpty)
    }

    /// Without a membership predicate there is no abstraction function, so nothing can
    /// hold the relation to account.
    @Test("Silent without an element-typed contains")
    func silentWithoutMembership() {
        let shapes = SetRelationModelPairing.candidates(in: [
            member("isDisjoint", param: "RangeSet<Bound>", returns: "Bool", label: "with")
        ])
        #expect(shapes.isEmpty)
    }

    /// **The `OptionSet` false-positive class, inherited from the sibling template's first
    /// measured run.** `OptionSet.contains(_ member: Self) -> Bool` is a *subset* test,
    /// not membership; read as membership the laws are false. The shared
    /// `membershipPredicate` gate requires the parameter NOT to be the carrier, and this
    /// pins that the reuse kept it. Confirmed on `stdlib/public/core`: zero OptionSet rows.
    @Test("A carrier-typed `contains` is not a membership predicate")
    func carrierTypedContainsRejected() {
        let shapes = SetRelationModelPairing.candidates(in: [
            member("contains", param: "OptionSetLike", returns: "Bool", on: "OptionSetLike"),
            member(
                "isDisjoint", param: "OptionSetLike", returns: "Bool",
                label: "with", on: "OptionSetLike"
            )
        ])
        #expect(shapes.isEmpty)
    }

    @Test("A mutating or non-Bool relation is not a relation")
    func shapeGates() {
        let mutating = SetRelationModelPairing.candidates(in: [
            member("contains", param: "Bound", returns: "Bool"),
            member(
                "isDisjoint", param: "RangeSet<Bound>", returns: "Bool",
                label: "with", isMutating: true
            )
        ])
        #expect(mutating.isEmpty)

        let nonBool = SetRelationModelPairing.candidates(in: [
            member("contains", param: "Bound", returns: "Bool"),
            member("isSubset", param: "RangeSet<Bound>", returns: "RangeSet<Bound>", label: "of")
        ])
        #expect(nonBool.isEmpty)
    }

    // MARK: - Explainability (PRD §4.5)

    /// The one-directional limitation is the honest half of this template and must be
    /// stated, or a green run reads as "the relation is correct" when it only means "no
    /// wrongly-true answer was caught".
    @Test("The caveats name the missing direction, the vacuity trap, and the kit boundary")
    func caveatsCarryTheLimits() {
        let shapes = SetRelationModelPairing.candidates(in: rangeSetLike())
        let caveats = shapes.first.map(SetRelationModelLawTemplate.makeCaveats(for:)) ?? []
        #expect(caveats.contains { $0.contains("ONE DIRECTION ONLY") })
        #expect(caveats.contains { $0.contains("existential") })
        #expect(caveats.contains { $0.contains("vacuously green") })
        #expect(caveats.contains { $0.contains("checkSetAlgebraPropertyLaws") })
    }

    /// Guarded laws are doubly collision-dependent — the guard has to hold *and* the
    /// element has to land where the operands disagree — so the narrowing rationale has to
    /// travel with the recipe.
    @Test("The generator recipe explains why a wide alphabet loses twice")
    func generatorRationale() {
        let shapes = SetRelationModelPairing.candidates(in: rangeSetLike())
        let recipes = shapes.first.map(SetRelationModelLawTemplate.makeGenerators(for:)) ?? []
        #expect(recipes.first?.rationale.contains("loses twice") == true)
    }

    @Test("Identity is stable and scoped to the relation")
    func identityIsStable() {
        let shapes = SetRelationModelPairing.candidates(in: rangeSetLike())
        let identities = shapes.map(SetRelationModelLawTemplate.makeIdentity(for:))
        #expect(Set(identities).count == 3, "one identity per relation")
        #expect(identities.first == shapes.first.map(SetRelationModelLawTemplate.makeIdentity(for:)))
    }
}
