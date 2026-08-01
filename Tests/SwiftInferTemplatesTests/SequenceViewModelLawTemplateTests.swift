import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The **sequence-view model law** — `(a == b) == a.elementsEqual(b)`.
///
/// The second of the two model-law families. `ModelLawTemplate` closed the membership line;
/// `fixtures/equatable-signal/README.md` left this one open pending an ordered-carrier
/// discriminator, because `Set` is a `Sequence` whose order is unspecified and the law is
/// false there.
@Suite("Sequence-view model law — holding a hand-written `==` to the type's own element order")
struct SequenceViewModelLawTemplateTests {

    private static let loc = SourceLocation(file: "OrderedSet+Equatable.swift", line: 27, column: 1)

    private func equalsOperator(
        on carrier: String,
        lhsType: String? = nil,
        rhsType: String? = nil,
        returns: String? = "Bool",
        bodyShape: EqualityBodyShape? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: "==",
            parameters: [
                Parameter(
                    label: nil, internalName: "left",
                    typeText: lhsType ?? carrier, isInout: false
                ),
                Parameter(
                    label: nil, internalName: "right",
                    typeText: rhsType ?? carrier, isInout: false
                )
            ],
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: true,
            location: Self.loc,
            containingTypeName: carrier,
            bodySignals: BodySignals(
                hasNonDeterministicCall: false,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: [],
                equalityBodyShape: bodyShape
            )
        )
    }

    private func hashFunction(on carrier: String) -> FunctionSummary {
        FunctionSummary(
            name: "hash",
            parameters: [
                Parameter(label: "into", internalName: "hasher", typeText: "inout Hasher", isInout: true)
            ],
            returnTypeText: nil,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: Self.loc,
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    private static let orderedConformances: [String: Set<String>] = [
        "OrderedSet": ["RandomAccessCollection", "ExpressibleByArrayLiteral", "Equatable", "Hashable"]
    ]

    // MARK: - It fires where the measured bugs live

    @Test("Fires on an element-determined ordered carrier with a hand-written ==")
    func firesOnOrderedCarrier() {
        let shapes = SequenceViewModelPairing.candidates(
            in: [equalsOperator(on: "OrderedSet")],
            inheritedTypesByName: Self.orderedConformances
        )
        #expect(shapes.count == 1)
        #expect(shapes.first?.typeName == "OrderedSet")
        #expect(shapes.first?.orderSignal == "RandomAccessCollection")

        let suggestion = shapes.first.flatMap(SequenceViewModelLawTemplate.suggest(for:))
        #expect(suggestion?.templateName == "sequence-view-model-law")
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely, "70 without the hash bonus")
    }

    /// Measured on the real corpora: every one of the seven firings carries the hash bonus,
    /// because `Hashable`'s contract ties `hash(into:)` to `==` and an author hand-writing one
    /// hand-writes the other.
    @Test("The hash bonus lifts it to Strong, which is what every real firing does")
    func hashBonusReachesStrong() {
        let shapes = SequenceViewModelPairing.candidates(
            in: [equalsOperator(on: "OrderedSet"), hashFunction(on: "OrderedSet")],
            inheritedTypesByName: Self.orderedConformances
        )
        #expect(shapes.first?.declaresCustomHash == true)
        let suggestion = shapes.first.flatMap(SequenceViewModelLawTemplate.suggest(for:))
        #expect(suggestion?.score.total == 80)
        #expect(suggestion?.score.tier == .strong)
    }

    // MARK: - The body-shape signal (EqualityBodyClassifier)

    /// Measured on the real corpora: 4 of the 7 firings have an `==` that already IS
    /// the sequence comparison — `Deque` returns `elementsEqual`, `Array` and
    /// `ContiguousArray` inline it over indices, `ArraySlice` over parallel iterators.
    /// The law restates their result expression, so they leave the default surface and
    /// stay available as regression guards under `--include-possible`.
    @Test("A body that already IS the comparison drops the suggestion to Possible")
    func vacuousBodyIsDemoted() {
        let equals = equalsOperator(on: "OrderedSet", bodyShape: .sequenceComparison(callee: "elementsEqual"))
        let shapes = SequenceViewModelPairing.candidates(
            in: [equals, hashFunction(on: "OrderedSet")],
            inheritedTypesByName: Self.orderedConformances
        )
        let suggestion = shapes.first.flatMap(SequenceViewModelLawTemplate.suggest(for:))
        #expect(suggestion?.score.total == 35, "80 less the 45-point vacuity penalty")
        #expect(suggestion?.score.tier == .possible)
    }

    /// The weight is set so the penalty dominates from EITHER configuration the
    /// template can produce, rather than being tuned to one of them.
    @Test("The penalty reaches Possible without the hash bonus too")
    func vacuousBodyIsDemotedWithoutHashBonus() {
        let equals = equalsOperator(on: "OrderedSet", bodyShape: .sequenceComparison(callee: "Array"))
        let shapes = SequenceViewModelPairing.candidates(
            in: [equals],
            inheritedTypesByName: Self.orderedConformances
        )
        let suggestion = shapes.first.flatMap(SequenceViewModelLawTemplate.suggest(for:))
        #expect(suggestion?.score.total == 25, "70 less the 45-point vacuity penalty")
        #expect(suggestion?.score.tier == .possible)
    }

    /// A projection keeps full tier — it is the shape three real bugs were found in,
    /// and the signal names the fields so a reader can check them.
    @Test("A projection body keeps Strong, and the fields are named")
    func projectionKeepsStrong() {
        let equals = equalsOperator(
            on: "OrderedSet",
            bodyShape: .storedFieldProjection(members: ["_count", "_storage"])
        )
        let shapes = SequenceViewModelPairing.candidates(
            in: [equals, hashFunction(on: "OrderedSet")],
            inheritedTypesByName: Self.orderedConformances
        )
        let suggestion = shapes.first.flatMap(SequenceViewModelLawTemplate.suggest(for:))
        #expect(suggestion?.score.tier == .strong)
        let details = suggestion?.score.signals.map(\.detail).joined(separator: " ") ?? ""
        #expect(details.contains("PROJECTION onto _count, _storage"))
    }

    // MARK: - It stays silent where the law is false

    /// The reason the family was not built before the discriminator existed. Proposing this on
    /// `Set` would ship a law that is false for a correct implementation.
    @Test("Silent on a SetAlgebra carrier — the law is FALSE there, not merely unproven")
    func silentOnSetAlgebra() {
        let shapes = SequenceViewModelPairing.candidates(
            in: [equalsOperator(on: "Set"), hashFunction(on: "Set")],
            inheritedTypesByName: [
                "Set": ["Collection", "Sequence", "SetAlgebra", "ExpressibleByArrayLiteral"]
            ]
        )
        #expect(shapes.isEmpty)
    }

    /// `Range`'s value outlives its elements: `5..<5` and `7..<7` are both empty and compare
    /// unequal, so the right-to-left direction of the biconditional is false.
    @Test("Silent on Range — ordered, but not determined by its elements")
    func silentOnRange() {
        let shapes = SequenceViewModelPairing.candidates(
            in: [equalsOperator(on: "Range")],
            inheritedTypesByName: [
                "Range": ["RandomAccessCollection", "BidirectionalCollection", "Equatable"]
            ]
        )
        #expect(shapes.isEmpty)
    }

    /// A synthesized `==` compares every stored member and cannot be a projection, so there is
    /// no projection bug to catch. No declared `==`, no suggestion.
    @Test("Silent when the carrier does not hand-write ==")
    func silentWithoutCustomEquals() {
        let shapes = SequenceViewModelPairing.candidates(
            in: [hashFunction(on: "OrderedSet")],
            inheritedTypesByName: Self.orderedConformances
        )
        #expect(shapes.isEmpty)
    }

    /// A heterogeneous `==` states a different claim, and `elementsEqual` across two element
    /// types is not the law we mean.
    @Test("Silent on a heterogeneous == (Substring == String)")
    func silentOnHeterogeneousEquals() {
        let shapes = SequenceViewModelPairing.candidates(
            in: [equalsOperator(on: "Substring", rhsType: "String")],
            inheritedTypesByName: [
                "Substring": ["RandomAccessCollection", "ExpressibleByArrayLiteral", "Equatable"]
            ]
        )
        #expect(shapes.isEmpty)
    }

    /// No conformance record at all means no verdict — an unresolvable carrier is silence,
    /// not a guess, matching `ProtocolCoverageMap`'s posture.
    @Test("Silent when the carrier's conformances are unknown")
    func silentWhenConformancesUnknown() {
        let shapes = SequenceViewModelPairing.candidates(
            in: [equalsOperator(on: "MysteryBag")],
            inheritedTypesByName: [:]
        )
        #expect(shapes.isEmpty)
    }

    // MARK: - Explainability is a first-class output (PRD §4.5)

    /// The vacuity hazard is invisible to the score and must be stated, or a reader counts a
    /// law that cannot fail as evidence that something was checked.
    @Test("The caveats name vacuity, the pair generator, and the kit's non-subsumption")
    func caveatsCarryTheHazards() {
        let shapes = SequenceViewModelPairing.candidates(
            in: [equalsOperator(on: "OrderedSet")],
            inheritedTypesByName: Self.orderedConformances
        )
        let caveats = shapes.first.map(SequenceViewModelLawTemplate.makeCaveats(for:)) ?? []
        #expect(caveats.contains { $0.contains("VACUOUS") })
        #expect(caveats.contains { $0.contains("DRAW PAIRS") })
        #expect(caveats.contains { $0.contains("checkEquatablePropertyLaws") })
        #expect(caveats.contains { $0.contains("(a == b) == a.elementsEqual(b)") })
    }

    /// The generator is collision-dependent, and CLAUDE.md's standing rule is that the
    /// narrowing rationale must live at the point of use or a later cleanup pass widens it
    /// back and the law goes quiet.
    @Test("The generator recipe carries the collision rationale")
    func generatorCarriesRationale() {
        let shapes = SequenceViewModelPairing.candidates(
            in: [equalsOperator(on: "OrderedSet")],
            inheritedTypesByName: Self.orderedConformances
        )
        let recipes = shapes.first.map(SequenceViewModelLawTemplate.makeGenerators(for:)) ?? []
        #expect(recipes.count == 1)
        #expect(recipes.first?.rationale.contains("MUST DRAW PAIRS") == true)
    }

    /// Identity is stable across runs so `accept` / `drift` can track the suggestion.
    @Test("Identity is stable and template-scoped")
    func identityIsStable() {
        let shapes = SequenceViewModelPairing.candidates(
            in: [equalsOperator(on: "OrderedSet")],
            inheritedTypesByName: Self.orderedConformances
        )
        guard let shape = shapes.first else {
            Issue.record("expected a shape")
            return
        }
        let first = SequenceViewModelLawTemplate.makeIdentity(for: shape)
        let second = SequenceViewModelLawTemplate.makeIdentity(for: shape)
        #expect(first == second)
    }
}
