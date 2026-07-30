import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The **model law** — an operation must agree with the semantics its name claims, checked
/// pointwise through `contains` rather than against the type's own algebra.
///
/// Built because two independent measurements converged on it: the `Equatable`-signal study
/// (three real projection bugs that pass 4/4 Equatable laws and die at trial ≤3 against a
/// model) and the swift.org `loops` population (`RangeSet` states five of these by hand, the
/// largest single `gap-with-witness` cluster in the study).
@Suite("Model law — membership homomorphism through `contains`")
struct ModelLawTemplateTests {

    private static let loc = SourceLocation(file: "RangeSet.swift", line: 10, column: 1)

    private func member(
        _ name: String,
        param: String,
        returns: String?,
        label: String? = nil,
        on carrier: String = "RangeSet",
        isMutating: Bool = false
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
            isStatic: false,
            location: Self.loc,
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    /// A `RangeSet`-shaped carrier: the four curated operations plus an element predicate.
    private func rangeSetLike() -> [FunctionSummary] {
        [
            member("contains", param: "Bound", returns: "Bool"),
            member("union", param: "RangeSet<Bound>", returns: "RangeSet<Bound>"),
            member("intersection", param: "RangeSet<Bound>", returns: "RangeSet<Bound>"),
            member("symmetricDifference", param: "RangeSet<Bound>", returns: "RangeSet<Bound>"),
            member("subtracting", param: "RangeSet<Bound>", returns: "RangeSet<Bound>")
        ]
    }

    @Test("the motivating shape fires on all four operations, at Strong")
    func rangeSetShapeFires() throws {
        let shapes = ModelLawPairing.candidates(in: rangeSetLike())
        #expect(shapes.count == 4)
        #expect(Set(shapes.map(\.form.rawValue))
            == ["union", "intersection", "symmetricDifference", "subtracting"])

        let union = try #require(shapes.first { $0.form == .union })
        #expect(union.elementTypeText == "Bound")
        #expect(union.typeName == "RangeSet")

        let suggestion = try #require(ModelLawTemplate.suggest(for: union))
        #expect(suggestion.templateName == "model-law")
        // 40 name + 30 shape + 10 cluster. Strong, so it shows without --include-possible —
        // which is the point: this is the gap the study measured, not a footnote.
        #expect(suggestion.score.total == 80)
        #expect(suggestion.score.tier == .strong)
    }

    /// The regression that the first measured run produced, at Strong tier, on real stdlib.
    ///
    /// `OptionSet.contains(_ member: Self) -> Bool` (`OptionSet.swift:216`) is a **subset
    /// test**, not membership. Read as membership the law is not merely unproven but FALSE:
    /// `x ⊆ (a ∪ b) ⟺ x ⊆ a ∨ x ⊆ b` fails for `x = {1,2}`, `a = {1}`, `b = {2}`.
    /// Three false positives, all Strong, all shown by default. This is the gate that killed
    /// them and it is the most load-bearing assertion in the suite.
    @Test("a (Self) -> Bool `contains` is a SUBSET TEST and must not be read as membership")
    func selfTypedContainsIsRejected() {
        let optionSetLike = [
            member("contains", param: "Self", returns: "Bool", on: "Fields"),
            member("union", param: "Self", returns: "Self", on: "Fields"),
            member("intersection", param: "Self", returns: "Self", on: "Fields"),
            member("symmetricDifference", param: "Self", returns: "Self", on: "Fields")
        ]
        #expect(ModelLawPairing.candidates(in: optionSetLike).isEmpty)
    }

    @Test("the spelled-out carrier form of the same mistake is also rejected")
    func carrierTypedContainsIsRejected() {
        let spelled = [
            member("contains", param: "Fields", returns: "Bool", on: "Fields"),
            member("union", param: "Fields", returns: "Fields", on: "Fields")
        ]
        #expect(ModelLawPairing.candidates(in: spelled).isEmpty)
    }

    @Test("without a membership predicate there is no law to state")
    func noContainsMeansNoLaw() {
        let noPredicate = [
            member("union", param: "RangeSet<Bound>", returns: "RangeSet<Bound>"),
            member("intersection", param: "RangeSet<Bound>", returns: "RangeSet<Bound>")
        ]
        #expect(ModelLawPairing.candidates(in: noPredicate).isEmpty)
    }

    @Test("`contains(where:)` takes a closure and is not the characteristic function")
    func labelledContainsIsRejected() {
        let closureForm = [
            member("contains", param: "(Bound) -> Bool", returns: "Bool", label: "where"),
            member("union", param: "RangeSet<Bound>", returns: "RangeSet<Bound>")
        ]
        #expect(ModelLawPairing.candidates(in: closureForm).isEmpty)
    }

    @Test("the mutating half is not paired — `formUnion` returns nothing to ask `contains` of")
    func mutatingFormIsNotPaired() {
        let mutating = [
            member("contains", param: "Bound", returns: "Bool"),
            member("formUnion", param: "RangeSet<Bound>", returns: nil, isMutating: true),
            member("union", param: "RangeSet<Bound>", returns: "RangeSet<Bound>", isMutating: true)
        ]
        #expect(ModelLawPairing.candidates(in: mutating).isEmpty)
    }

    @Test("a lone set operation scores Likely, not Strong — one name is not a Boolean algebra")
    func loneOperationDoesNotGetTheClusterBonus() throws {
        let lone = [
            member("contains", param: "Bound", returns: "Bool"),
            member("union", param: "RangeSet<Bound>", returns: "RangeSet<Bound>")
        ]
        let shape = try #require(ModelLawPairing.candidates(in: lone).first)
        #expect(shape.siblingOperationCount == 1)
        let suggestion = try #require(ModelLawTemplate.suggest(for: shape))
        #expect(suggestion.score.total == 70)
        #expect(suggestion.score.tier == .likely)
    }

    @Test("each operation states its own Boolean combinator")
    func combinatorsAreCorrect() {
        let expected: [ModelLawPairing.SetOperation: String] = [
            .union: "a.contains(x) || b.contains(x)",
            .intersection: "a.contains(x) && b.contains(x)",
            .symmetricDifference: "a.contains(x) != b.contains(x)",
            .subtracting: "a.contains(x) && !b.contains(x)"
        ]
        for (form, text) in expected {
            #expect(form.membershipExpression("a", "b", element: "x") == text)
        }
        // Every case is covered, so a new operation cannot be added without a combinator.
        #expect(Set(expected.keys) == Set(ModelLawPairing.SetOperation.allCases))
    }

    /// The caveat that stops the law being green-but-vacuous. Per CLAUDE.md a
    /// collision-dependent property is *invisible* to a generator drawing from a realistic
    /// domain — measured once already, where a commutativity law known to be false reported
    /// `bothPass` at 100 trials until the alphabet was narrowed.
    @Test("the vacuity trap is stated in the caveats AND in the generator rationale")
    func vacuityTrapIsSurfaced() throws {
        let shape = try #require(ModelLawPairing.candidates(in: rangeSetLike()).first)
        let suggestion = try #require(ModelLawTemplate.suggest(for: shape))

        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("vacuously"))
        #expect(caveats.contains("narrow alphabet"))
        // And the independence claim, so nobody "fixes" this as a kit double-report.
        #expect(caveats.contains("checkSetAlgebraPropertyLaws"))

        let recipe = try #require(ModelLawTemplate.makeGenerators(for: shape).first)
        #expect(recipe.typeName == "Bound")
        #expect(recipe.rationale.contains("NARROW"))
    }

    @Test("the abstraction function is named in why-suggested, with its location")
    func abstractionFunctionIsCited() throws {
        let shape = try #require(ModelLawPairing.candidates(in: rangeSetLike()).first)
        let suggestion = try #require(ModelLawTemplate.suggest(for: shape))
        let why = suggestion.explainability.whySuggested.joined(separator: "\n")
        #expect(why.contains("contains(_:) -> Bool"))
        #expect(why.contains("RangeSet.swift:10"))
    }

    @Test("distinct operations on one carrier get distinct identities")
    func identitiesAreDistinct() {
        let shapes = ModelLawPairing.candidates(in: rangeSetLike())
        let identities = shapes.compactMap { ModelLawTemplate.suggest(for: $0)?.identity }
        #expect(Set(identities.map(\.canonicalInput)).count == shapes.count)
    }

    @Test("generic spelling of the carrier is matched, not compared literally")
    func genericCarrierSpellingsMatch() {
        #expect(ModelLawPairing.stripGenerics("RangeSet<Bound>") == "RangeSet")
        #expect(ModelLawPairing.stripGenerics("RangeSet") == "RangeSet")
        #expect(ModelLawPairing.matchesCarrier("Self", carrier: "RangeSet"))
        #expect(ModelLawPairing.matchesCarrier("RangeSet<Bound>", carrier: "RangeSet"))
        #expect(!ModelLawPairing.matchesCarrier("Bound", carrier: "RangeSet"))
    }
}
