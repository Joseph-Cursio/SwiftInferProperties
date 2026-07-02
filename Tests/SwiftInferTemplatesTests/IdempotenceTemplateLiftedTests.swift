import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("IdempotenceTemplate — V1.19.B lift admission (no-param + x-curried)")
struct IdempotenceTemplateLiftedTests {

    // MARK: - Helpers

    /// Test-only parameter spec — three fields (label, type, isInout)
    /// avoid the `large_tuple` lint warning. Mirrors the `Parameter` shape
    /// without the `internalName` field (the test helper auto-numbers).
    struct ParamSpec {
        let label: String?
        let type: String
        let isInout: Bool

        init(_ label: String?, _ type: String, isInout: Bool = false) {
            self.label = label
            self.type = type
            self.isInout = isInout
        }
    }

    private func summary(
        _ name: String,
        params: [ParamSpec] = [],
        returnType: String? = "Void",
        isMutating: Bool = true,
        containingType: String? = "Bag",
        line: Int = 1
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params.enumerated().map { index, spec in
                Parameter(
                    label: spec.label,
                    internalName: "p\(index)",
                    typeText: spec.type,
                    isInout: spec.isInout
                )
            },
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: isMutating,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: line, column: 1),
            containingTypeName: containingType,
            bodySignals: .empty
        )
    }

    private func valueSemanticResolver(carrier: String = "Bag") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "items", typeName: "[Int]")]
            )
        ])
    }

    private func liftedNoParam(
        _ name: String = "removeAll",
        carrier: String = "Bag"
    ) -> LiftedTransformation {
        let resolver = valueSemanticResolver(carrier: carrier)
        return LiftedTransformation.lift(
            summary(name, containingType: carrier),
            carrierKindResolver: resolver
        )!
    }

    private func liftedParamMatchesCarrier(
        _ name: String = "formUnion",
        carrier: String = "Bag"
    ) -> LiftedTransformation {
        let resolver = valueSemanticResolver(carrier: carrier)
        return LiftedTransformation.lift(
            summary(
                name,
                params: [ParamSpec(nil, carrier)],
                containingType: carrier
            ),
            carrierKindResolver: resolver
        )!
    }

    // MARK: - Admission shapes

    @Test("No-param mutating method (Set.removeAll-shape) yields a Likely suggestion")
    func noParamLiftAdmits() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedNoParam("removeAll"),
            carrierKindResolver: valueSemanticResolver()
        ))
        // 30 type-symmetry + 5 carrier + 10 lifted = 45 → Likely (40-74).
        #expect(suggestion.score.total == 45)
        #expect(suggestion.score.tier == .likely)
        #expect(suggestion.templateName == "idempotence")
    }

    @Test("Param-matches-carrier (Set.formUnion-shape) yields a Likely suggestion")
    func xCurriedLiftAdmits() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedParamMatchesCarrier("formUnion"),
            carrierKindResolver: valueSemanticResolver()
        ))
        // 30 type-symmetry + 5 carrier + 10 lifted = 45 → Likely.
        // SetAlgebra-shape veto does NOT fire here because `Bag` is not
        // declared as `: SetAlgebra` in the test corpus — this is the
        // generic value-semantic struct case.
        #expect(suggestion.score.total == 45)
        #expect(suggestion.score.tier == .likely)
    }

    @Test("Single param with type ≠ carrier is NOT an idempotence candidate")
    func paramNotMatchingCarrierRejected() {
        // `mutating func increment(by: Int)` on `struct Counter` — Int ≠
        // Counter. Idempotence on this would be `op'(op'(s, x), x) == op'(s, x)`
        // which is false (doubles). V1.19.C handles via CompositionTemplate.
        let resolver = valueSemanticResolver(carrier: "Counter")
        let lifted = LiftedTransformation.lift(
            summary(
                "increment",
                params: [ParamSpec("by", "Int")],
                containingType: "Counter"
            ),
            carrierKindResolver: resolver
        )!
        #expect(IdempotenceTemplate.suggest(
            forLifted: lifted,
            carrierKindResolver: resolver
        ) == nil)
    }

    // MARK: - Callee-shape signal on lifted evidence

    @Test("A no-param lifted mutating pick carries the mutating-instance callee-shape signal")
    func liftedNoParamCarriesCalleeShapeSignal() throws {
        // `mutating func removeAll()` on the value-semantic `Bag`. The evidence
        // must mark it instance + mutating + nullary so the verify emitter routes
        // it to `var copy = value; copy.removeAll()` for *any* carrier — not just
        // the curated OrderedCollections set.
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedNoParam("removeAll"),
            carrierKindResolver: valueSemanticResolver()
        ))
        let evidence = try #require(suggestion.evidence.first)
        #expect(evidence.isInstanceMethod)
        #expect(evidence.isMutatingMethod)
        #expect(evidence.isNullary)
        #expect(evidence.returnsSelfType == false)
    }

    @Test("An arg-bearing lifted mutating pick is not marked nullary (stays off the receiver shape)")
    func liftedArgBearingNotNullary() throws {
        // `mutating func formUnion(_ other: Bag)` — idempotent, but its emit needs
        // an argument, so `isNullary` must be false so the nullary `copy.method()`
        // shape (which wouldn't compile) is not selected.
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedParamMatchesCarrier("formUnion"),
            carrierKindResolver: valueSemanticResolver()
        ))
        let evidence = try #require(suggestion.evidence.first)
        #expect(evidence.isInstanceMethod)
        #expect(evidence.isMutatingMethod)
        #expect(evidence.isNullary == false)
    }

    @Test("Two-param mutating method is NOT an idempotence candidate")
    func twoParamRejected() {
        let resolver = valueSemanticResolver()
        let lifted = LiftedTransformation.lift(
            summary(
                "merge",
                params: [
                    ParamSpec(nil, "Bag"),
                    ParamSpec("with", "Int")
                ]
            ),
            carrierKindResolver: resolver
        )!
        #expect(IdempotenceTemplate.suggest(
            forLifted: lifted,
            carrierKindResolver: resolver
        ) == nil)
    }

    @Test("Inout param disqualifies (aliasing breaks the lift's value-semantic guarantee)")
    func inoutParamRejected() {
        let resolver = valueSemanticResolver()
        let lifted = LiftedTransformation.lift(
            summary(
                "consume",
                params: [ParamSpec(nil, "Bag", isInout: true)]
            ),
            carrierKindResolver: resolver
        )!
        #expect(IdempotenceTemplate.suggest(
            forLifted: lifted,
            carrierKindResolver: resolver
        ) == nil)
    }
}
