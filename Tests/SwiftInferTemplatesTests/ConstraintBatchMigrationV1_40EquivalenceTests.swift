import PropertyLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

/// V1.40.F — equivalence tests for the v1.40 batch migration of the
/// last 5 templates (InversePair non-lifted + lifted, IdentityElement
/// non-lifted + lifted, Composition) — completing the 10-template
/// Constraint Engine refactor (PRD §20.2). Verifies that:
///   - InversePair / Composition / IdempotenceLifted-style migrations
///     produce bit-for-bit identical Suggestion via the wrapper +
///     via ConstraintRunner.
///   - IdentityElement (non-lifted + lifted) use the **wrapper
///     migration pattern** — the Constraint drives signals + evidence
///     + identity + carrier; the wrapper rebuilds Suggestion with
///     bespoke explainability to preserve the no-space identity-
///     evidence rendering.
@Suite("InversePairTemplate non-lifted — V1.40.F Constraint equivalence")
struct InversePairConstraintEquivalenceTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func summary(
        name: String,
        param: String,
        ret: String,
        container: String? = "Foo"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "x", typeText: param, isInout: false)],
            returnTypeText: ret,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: loc,
            containingTypeName: container,
            bodySignals: .empty
        )
    }

    @Test("V1.40.F — InversePair non-lifted: wrapper matches Constraint output across corpus")
    func equivalence() {
        let corpus: [(label: String, pair: FunctionPair)] = [
            ("encode_decode_userType", FunctionPair(
                forward: Self.summary(name: "encode", param: "MyType", ret: "String"),
                reverse: Self.summary(name: "decode", param: "String", ret: "MyType")
            )),
            ("transform_untransform", FunctionPair(
                forward: Self.summary(name: "transform", param: "Token", ret: "Token"),
                reverse: Self.summary(name: "untransform", param: "Token", ret: "Token")
            ))
        ]
        for (label, pair) in corpus {
            let wrapper = InversePairTemplate.suggest(for: pair)
            let runner = ConstraintRunner.suggest(
                constraint: InversePairTemplate.makeConstraint(
                    vocabulary: .empty,
                    equatableResolver: nil,
                    inheritedTypesByName: [:],
                    carrierKindResolver: nil
                ),
                subject: pair
            )
            #expect(wrapper == runner, "[\(label)] disagree")
        }
    }
}

@Suite("InversePairTemplate+Lifted — V1.40.F Constraint equivalence")
struct InversePairLiftedEquivTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func resolver(carrier: String = "MyBag") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier, kind: .struct, inheritedTypes: [],
                location: loc, storedMembers: [StoredMember(name: "x", typeName: "Int")]
            )
        ])
    }

    private static func makeLiftedInversePair() -> LiftedInversePair? {
        let resolver = resolver()
        let insertSummary = FunctionSummary(
            name: "insert",
            parameters: [Parameter(label: nil, internalName: "x", typeText: "Int", isInout: false)],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: loc, containingTypeName: "MyBag", bodySignals: .empty
        )
        let removeSummary = FunctionSummary(
            name: "remove",
            parameters: [Parameter(label: nil, internalName: "x", typeText: "Int", isInout: false)],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: loc, containingTypeName: "MyBag", bodySignals: .empty
        )
        let forward = LiftedTransformation.lift(insertSummary, carrierKindResolver: resolver)!
        let reverse = LiftedTransformation.lift(removeSummary, carrierKindResolver: resolver)!
        return LiftedInversePair(
            forward: forward,
            reverse: reverse,
            pairName: LiftedInversePair.NamePair(lhs: "insert", rhs: "remove")
        )
    }

    @Test("V1.40.F — InversePair lifted: wrapper matches Constraint output")
    func equivalence() throws {
        let pair = try #require(Self.makeLiftedInversePair())
        let resolver = Self.resolver()
        let wrapper = InversePairTemplate.suggest(
            forLifted: pair, carrierKindResolver: resolver
        )
        let runner = ConstraintRunner.suggest(
            constraint: InversePairTemplate.makeLiftedConstraint(carrierKindResolver: resolver),
            subject: pair
        )
        #expect(wrapper == runner)
    }
}

@Suite("IdentityElementTemplate non-lifted — V1.40.F wrapper-pattern equivalence")
struct IdentityElementEquivTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    @Test("V1.40.F — IdentityElement non-lifted: wrapper preserves no-space identity-evidence rendering")
    func wrapperPreservesNoSpaceRendering() throws {
        let pair = makeIdentityElementPair(
            opName: "+",
            paramTypes: ("Int", "Int"),
            returnType: "Int",
            identityName: "zero",
            identityType: "Int"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        // Identity-evidence row should be `"zero: Int — Test.swift:5"` (no space
        // between "zero" and ":"). The runner's canonical assembly would emit
        // `"zero : Int — Test.swift:5"` (with space), which the wrapper bypasses.
        let identityLine = suggestion.explainability.whySuggested.first { $0.contains("zero") }
        #expect(identityLine != nil)
        #expect(!(identityLine?.contains("zero :") ?? true), "wrapper should preserve no-space rendering")
        #expect(identityLine?.contains("zero:") == true)
    }
}

@Suite("CompositionTemplate — V1.40.F Constraint equivalence")
struct CompositionConstraintEquivalenceTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    @Test("V1.40.F — Composition: wrapper matches Constraint output")
    func equivalence() throws {
        let resolver = CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: "Counter", kind: .struct, inheritedTypes: [],
                location: Self.loc, storedMembers: [StoredMember(name: "value", typeName: "Int")]
            )
        ])
        let summary = FunctionSummary(
            name: "increment",
            parameters: [Parameter(label: "by", internalName: "amount", typeText: "Int", isInout: false)],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: Self.loc, containingTypeName: "Counter", bodySignals: .empty
        )
        let lifted = try #require(LiftedTransformation.lift(summary, carrierKindResolver: resolver))
        let wrapper = CompositionTemplate.suggest(forLifted: lifted, carrierKindResolver: resolver)
        let runner = ConstraintRunner.suggest(
            constraint: CompositionTemplate.makeConstraint(
                vocabulary: .empty, carrierKindResolver: resolver
            ),
            subject: lifted
        )
        #expect(wrapper == runner)
    }
}
