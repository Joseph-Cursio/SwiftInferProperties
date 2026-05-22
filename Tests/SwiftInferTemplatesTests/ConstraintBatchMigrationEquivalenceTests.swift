import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.38.D — equivalence tests for the v1.38 batch migrations of
/// Associativity / InvariantPreservation / DualStyleConsistency to
/// the Constraint Engine (PRD §20.2). Each per-template suite asserts
/// `wrapper-suggest == ConstraintRunner.suggest(constraint:)` on
/// representative fixtures, guaranteeing the migration is bit-for-bit
/// equivalence-preserving.

@Suite("AssociativityTemplate — V1.38.D Constraint equivalence")
struct AssociativityConstraintEquivalenceTests {

    private static let location = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func summary(name: String, isMutating: Bool = false) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "Int", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "Int", isInout: false)
            ],
            returnTypeText: "Int",
            isThrows: false, isAsync: false, isMutating: isMutating, isStatic: false,
            location: location,
            containingTypeName: "Foo",
            bodySignals: .empty
        )
    }

    @Test("V1.38.D — Associativity: wrapper matches Constraint output across corpus")
    func equivalence() {
        let corpus: [(label: String, summary: FunctionSummary)] = [
            ("curated_combine", Self.summary(name: "combine")),
            ("curated_merge", Self.summary(name: "merge")),
            ("bare_userOp", Self.summary(name: "someOp")),
            ("mutating_combine", Self.summary(name: "combine", isMutating: true))
        ]
        for (label, summary) in corpus {
            let wrapper = AssociativityTemplate.suggest(for: summary)
            let constraint = AssociativityTemplate.makeConstraint(
                vocabulary: .empty,
                reducerOps: [],
                inheritedTypesByName: [:]
            )
            let runner = ConstraintRunner.suggest(constraint: constraint, subject: summary)
            #expect(wrapper == runner, "[\(label)] disagree")
        }
    }

    @Test("V1.38.D — Associativity: runtime inputs propagate through the constraint")
    func runtimeInputsPropagate() throws {
        let summary = Self.summary(name: "myOp")
        // reducerOps including the op name should fire the reducer-usage signal
        let suggestion = try #require(AssociativityTemplate.suggest(
            for: summary,
            vocabulary: .empty,
            reducerOps: ["myOp"],
            inheritedTypesByName: [:]
        ))
        let reducerSignal = suggestion.score.signals.first { $0.kind == .reduceFoldUsage }
        #expect(reducerSignal != nil, "reducer-usage signal should fire when op is in reducerOps")
    }

    @Test("V1.38.D — Associativity: caveats always include FP advisory or fallback (3 entries)")
    func caveatsConstantCount() throws {
        let suggestion = try #require(AssociativityTemplate.suggest(for: Self.summary(name: "combine")))
        #expect(suggestion.explainability.whyMightBeWrong.count == 3)
    }
}

@Suite("InvariantPreservationTemplate — V1.38.D Constraint equivalence")
struct InvariantPreservationEquivTests {

    private static let location = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func summary(
        name: String = "apply",
        invariantKeypath: String? = nil,
        bodySignals: BodySignals = .empty
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: "x", typeText: "Foo", isInout: false)
            ],
            returnTypeText: "Foo",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: location,
            containingTypeName: "Foo",
            bodySignals: bodySignals,
            invariantKeypath: invariantKeypath
        )
    }

    @Test("V1.38.D — InvariantPreservation: wrapper matches Constraint output across corpus")
    func equivalence() {
        let corpus: [(label: String, summary: FunctionSummary)] = [
            ("missingKeypath_noFire", Self.summary()),
            ("withKeypath_isValid", Self.summary(invariantKeypath: "\\.isValid")),
            ("nonDeterministic_veto", Self.summary(
                invariantKeypath: "\\.isValid",
                bodySignals: BodySignals(
                    hasNonDeterministicCall: true,
                    hasSelfComposition: false,
                    nonDeterministicAPIsDetected: ["Date()"]
                )
            ))
        ]
        for (label, summary) in corpus {
            let wrapper = InvariantPreservationTemplate.suggest(for: summary)
            let runner = ConstraintRunner.suggest(
                constraint: InvariantPreservationTemplate.makeConstraint(),
                subject: summary
            )
            #expect(wrapper == runner, "[\(label)] disagree")
        }
    }

    @Test("V1.38.D — InvariantPreservation: missing keypath gate returns nil")
    func missingKeypathReturnsNil() {
        #expect(InvariantPreservationTemplate.suggest(for: Self.summary()) == nil)
    }

    @Test("V1.38.D — InvariantPreservation: keypath flows into caveat text")
    func caveatMentionsKeypath() throws {
        let suggestion = try #require(
            InvariantPreservationTemplate.suggest(for: Self.summary(invariantKeypath: "\\.isHealthy"))
        )
        let keypathCaveat = suggestion.explainability.whyMightBeWrong[0]
        #expect(keypathCaveat.contains("\\.isHealthy"))
    }
}

@Suite("DualStyleConsistencyTemplate — V1.38.D Constraint equivalence")
struct DualStyleConsistencyEquivTests {

    private static let location = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func makePair(
        mutatingName: String,
        nonMutatingName: String
    ) -> DualStylePair {
        let mut = FunctionSummary(
            name: mutatingName,
            parameters: [
                Parameter(label: nil, internalName: "other", typeText: "Self", isInout: false)
            ],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: location,
            containingTypeName: "MySet",
            bodySignals: .empty
        )
        let nonMut = FunctionSummary(
            name: nonMutatingName,
            parameters: [
                Parameter(label: nil, internalName: "other", typeText: "Self", isInout: false)
            ],
            returnTypeText: "Self",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: location,
            containingTypeName: "MySet",
            bodySignals: .empty
        )
        return DualStylePair(mutatingMember: mut, nonMutatingMember: nonMut, rule: .formPrefixToBare)
    }

    @Test("V1.38.D — DualStyleConsistency: wrapper matches Constraint output across corpus")
    func equivalence() {
        let corpus: [(label: String, pair: DualStylePair)] = [
            ("formUnion_union", Self.makePair(mutatingName: "formUnion", nonMutatingName: "union")),
            ("subtract_subtracting", Self.makePair(mutatingName: "subtract", nonMutatingName: "subtracting")),
            (
                "formIntersection_intersection",
                Self.makePair(mutatingName: "formIntersection", nonMutatingName: "intersection")
            )
        ]
        for (label, pair) in corpus {
            let wrapper = DualStyleConsistencyTemplate.suggest(for: pair, carrierKindResolver: nil)
            let runner = ConstraintRunner.suggest(
                constraint: DualStyleConsistencyTemplate.makeConstraint(carrierKindResolver: nil),
                subject: pair
            )
            #expect(wrapper == runner, "[\(label)] disagree")
        }
    }

    @Test("V1.38.D — DualStyleConsistency: 2 constant caveats")
    func caveatsConstant() throws {
        let suggestion = try #require(
            DualStyleConsistencyTemplate.suggest(
                for: Self.makePair(mutatingName: "formUnion", nonMutatingName: "union")
            )
        )
        #expect(suggestion.explainability.whyMightBeWrong.count == 2)
    }
}
