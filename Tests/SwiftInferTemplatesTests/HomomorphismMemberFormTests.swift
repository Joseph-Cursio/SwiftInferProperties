import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The **member form** of the additive-measure homomorphism —
/// `(a + b).count == a.count + b.count`.
///
/// `HomomorphismTemplate`'s original gate wants a free function `[T] -> Int`. Nobody
/// writes that in Swift; they write `var count: Int`. Measured across eight corpora and
/// ~55,000 functions, the template fired **zero times** (findings §10) — built for a
/// shape the language does not use, and undetected because a dead template and a
/// correctly-silent one produce identical output.
@Suite("Homomorphism, member form — a measure distributes over a free join")
struct HomomorphismMemberFormTests {

    private static let loc = SourceLocation(file: "Deque.swift", line: 20, column: 1)

    private func measure(
        _ name: String = "count",
        on carrier: String = "Deque",
        returns: String = "Int",
        parameters: [Parameter] = [],
        isMutating: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name, parameters: parameters, returnTypeText: returns,
            isThrows: false, isAsync: false, isMutating: isMutating, isStatic: false,
            location: Self.loc, containingTypeName: carrier, bodySignals: .empty
        )
    }

    private func join(
        _ name: String,
        on carrier: String = "Deque",
        returns: String? = nil,
        isMutating: Bool = false,
        parameterType: String? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(
                    label: nil, internalName: "other",
                    typeText: parameterType ?? carrier, isInout: false
                )
            ],
            returnTypeText: returns ?? (isMutating ? nil : carrier),
            isThrows: false, isAsync: false, isMutating: isMutating, isStatic: false,
            location: Self.loc, containingTypeName: carrier, bodySignals: .empty
        )
    }

    // MARK: - The shape the original gate could not see

    @Test("A member count with a value-returning + fires")
    func valueJoinFires() {
        let shapes = HomomorphismMemberPairing.candidates(
            in: [measure(), join("+")], inheritedTypesByName: ["Deque": ["Equatable"]]
        )
        #expect(shapes.count == 1)
        #expect(shapes.first?.lawText == "(a + b).count == a.count + b.count")

        let suggestion = shapes.first.flatMap(HomomorphismTemplate.suggestMemberForm(for:))
        // Same template name as the free-function form: it is the same law family, so the
        // health census should show one template going 0 -> N, not a sibling appearing.
        #expect(suggestion?.templateName == "homomorphism")
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("A mutating append states the law as a mutation")
    func mutatingJoinFires() {
        let shapes = HomomorphismMemberPairing.candidates(
            in: [measure(on: "Data"), join("append", on: "Data", isMutating: true)],
            inheritedTypesByName: ["Data": ["Equatable"]]
        )
        #expect(shapes.first?.concatenationIsMutating == true)
        #expect(shapes.first?.lawText.contains("var c = a; c.append(b)") == true)
    }

    @Test("Both halves are required — a measure alone is not a homomorphism")
    func measureAloneDeclined() {
        #expect(HomomorphismMemberPairing.candidates(
            in: [measure()], inheritedTypesByName: ["Deque": ["Equatable"]]
        ).isEmpty)
        #expect(HomomorphismMemberPairing.candidates(
            in: [join("+")], inheritedTypesByName: ["Deque": ["Equatable"]]
        ).isEmpty)
    }

    // MARK: - The exclusions, carried over from the free-function form

    /// `String.count` is grapheme count, and `"e" + "◌́"` is ONE grapheme, not two — so
    /// the measure is not additive across a join. `BigString` is a rope of `Character`s
    /// and inherits exactly that.
    @Test(
        "Grapheme-counting carriers are excluded",
        arguments: ["String", "BigString", "AttributedString"]
    )
    func graphemeCarriersExcluded(carrier: String) {
        let shapes = HomomorphismMemberPairing.candidates(
            in: [measure(on: carrier), join("+", on: carrier)],
            inheritedTypesByName: [carrier: ["Equatable"]]
        )
        #expect(shapes.isEmpty)
    }

    /// The exclusion is textual, so a scalar view whose count IS additive gets caught
    /// too. Pinned as a KNOWN COST rather than left to be rediscovered: a missed law is
    /// the conservative direction, and this arm going red means someone made the rule
    /// structural, which is an improvement rather than a regression.
    @Test("The textual rule over-excludes a scalar view — a known, accepted cost")
    func scalarViewOverExcluded() {
        let shapes = HomomorphismMemberPairing.candidates(
            in: [
                measure(on: "BigString.UnicodeScalarView"),
                join("+", on: "BigString.UnicodeScalarView")
            ],
            inheritedTypesByName: [:]
        )
        #expect(shapes.isEmpty, "over-excluded by the `String` marker — see the type doc")
    }

    /// `|A ∪ B| <= |A| + |B|`, with equality only when disjoint. Vetoed twice over: a
    /// `SetAlgebra` conformance, and `formUnion` never counting as a free join.
    @Test("Set-like carriers are excluded — the measure is sub-additive")
    func setLikeExcluded() {
        let byConformance = HomomorphismMemberPairing.candidates(
            in: [measure(on: "Bag"), join("+", on: "Bag")],
            inheritedTypesByName: ["Bag": ["SetAlgebra"]]
        )
        #expect(byConformance.isEmpty)

        let byVerb = HomomorphismMemberPairing.candidates(
            in: [measure(on: "Bag"), join("formUnion", on: "Bag", isMutating: true)],
            inheritedTypesByName: ["Bag": ["Equatable"]]
        )
        #expect(byVerb.isEmpty)
    }

    // MARK: - Shape gates

    @Test("A non-integer measure cannot be additive under exact ==")
    func nonIntegerMeasureDeclined() {
        let shapes = HomomorphismMemberPairing.candidates(
            in: [measure(returns: "Double"), join("+")],
            inheritedTypesByName: ["Deque": ["Equatable"]]
        )
        #expect(shapes.isEmpty)
    }

    @Test("A measure taking arguments is not the nullary member form")
    func parameterisedMeasureDeclined() {
        let shapes = HomomorphismMemberPairing.candidates(
            in: [
                measure(parameters: [
                    Parameter(
                        label: "where", internalName: "p",
                        typeText: "(Element) -> Bool", isInout: false
                    )
                ]),
                join("+")
            ],
            inheritedTypesByName: ["Deque": ["Equatable"]]
        )
        #expect(shapes.isEmpty)
    }

    /// The join has to combine the carrier with itself. `Deque + Element` is an append of
    /// one item, where the law would need `+ 1` rather than `+ b.count`.
    @Test("A join with a non-carrier operand is declined")
    func nonCarrierJoinDeclined() {
        let shapes = HomomorphismMemberPairing.candidates(
            in: [measure(), join("+", parameterType: "Element")],
            inheritedTypesByName: ["Deque": ["Equatable"]]
        )
        #expect(shapes.isEmpty)
    }

    // MARK: - Explainability (PRD §4.5)

    @Test("The caveats name the free-join requirement and the grapheme trap")
    func caveatsCarryTheLimits() {
        let shapes = HomomorphismMemberPairing.candidates(
            in: [measure(), join("+")], inheritedTypesByName: ["Deque": ["Equatable"]]
        )
        let caveats = shapes.first.map(HomomorphismTemplate.makeMemberCaveats(for:)) ?? []
        #expect(caveats.contains { $0.contains("THE JOIN MUST BE FREE") })
        #expect(caveats.contains { $0.contains("SUB-additive") })
        #expect(caveats.contains { $0.contains("ONE grapheme, not two") })
        #expect(caveats.contains { $0.contains("GENERATE THE JOIN, NOT THE OPERANDS") })
    }

    @Test("Identity is stable and distinct from the free-function form")
    func identityIsStableAndScoped() {
        let shapes = HomomorphismMemberPairing.candidates(
            in: [measure(), join("+")], inheritedTypesByName: ["Deque": ["Equatable"]]
        )
        guard let shape = shapes.first else {
            Issue.record("expected a shape")
            return
        }
        let identity = HomomorphismTemplate.makeMemberIdentity(for: shape)
        #expect(identity.canonicalInput.contains("member"))
        #expect(identity == HomomorphismTemplate.makeMemberIdentity(for: shape))
    }
}
