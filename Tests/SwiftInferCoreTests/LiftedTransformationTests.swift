import PropertyLawCore
import Testing
@testable import SwiftInferCore

@Suite("LiftedTransformation — V1.19.A admission gate + shadow-form derivation")
struct LiftedTransformationTests {

    // MARK: - Helpers

    private func summary(
        _ name: String,
        params: [(label: String?, type: String)] = [],
        returnType: String? = "Void",
        isMutating: Bool = true,
        containingType: String? = "Counter",
        line: Int = 1,
        file: String = "Test.swift"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params.enumerated().map { index, parameter in
                Parameter(
                    label: parameter.label,
                    internalName: "p\(index)",
                    typeText: parameter.type,
                    isInout: false
                )
            },
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: isMutating,
            isStatic: false,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: containingType,
            bodySignals: .empty
        )
    }

    private func decl(
        _ name: String,
        _ kind: TypeDecl.Kind = .struct,
        members: [StoredMember] = []
    ) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: kind,
            inheritedTypes: [],
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            storedMembers: members
        )
    }

    private func valueSemanticResolver(carrier: String = "Counter") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            decl(carrier, .struct, members: [StoredMember(name: "value", typeName: "Int")])
        ])
    }

    private func referenceTypeResolver(carrier: String = "Service") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [decl(carrier, TypeDecl.Kind.class)])
    }

    // MARK: - Strict admission gate

    @Test("Mutating method on a value-semantic struct is admitted")
    func valueSemanticAdmits() throws {
        let resolver = valueSemanticResolver()
        let mutator = summary(
            "increment",
            params: [(label: "by", type: "Int")]
        )
        let lifted = try #require(LiftedTransformation.lift(mutator, carrierKindResolver: resolver))
        #expect(lifted.carrier == "Counter")
        #expect(lifted.originalSummary == mutator)
    }

    @Test("Non-mutating method is rejected (no lift needed)")
    func nonMutatingRejected() {
        let resolver = valueSemanticResolver()
        let nonMutator = summary("snapshot", returnType: "Int", isMutating: false)
        #expect(LiftedTransformation.lift(nonMutator, carrierKindResolver: resolver) == nil)
    }

    @Test("Top-level mutating function (nil container) is rejected")
    func topLevelRejected() {
        let resolver = valueSemanticResolver()
        // Top-level functions can't be `mutating` in Swift, but defensively
        // test the gate.
        let topLevel = summary("munge", containingType: nil)
        #expect(LiftedTransformation.lift(topLevel, carrierKindResolver: resolver) == nil)
    }

    @Test("Reference-type carrier is rejected (strict gate per v1.19 plan #2)")
    func referenceTypeRejected() {
        // Swift forbids `mutating` on classes; defensive test that even if
        // a class-typed carrier somehow appeared with isMutating=true, the
        // gate would reject. Real-world: equivalent shape with `func`
        // mutating internal `var` on a class is also rejected because
        // the carrier-kind resolver classes it as `.referenceType`.
        let resolver = referenceTypeResolver()
        let mutator = summary("mutate", containingType: "Service")
        #expect(LiftedTransformation.lift(mutator, carrierKindResolver: resolver) == nil)
    }

    @Test("Mixed carrier (struct with closure-typed stored member) is rejected")
    func mixedCarrierRejected() {
        let resolver = CarrierKindResolver(typeDecls: [
            decl("Bag", .struct, members: [StoredMember(name: "callback", typeName: "() -> Void")])
        ])
        let mutator = summary("update", containingType: "Bag")
        #expect(LiftedTransformation.lift(mutator, carrierKindResolver: resolver) == nil)
    }

    @Test("Unknown carrier (corpus has no TypeDecl for it) is rejected")
    func unknownCarrierRejected() {
        let resolver = CarrierKindResolver(typeDecls: [])
        let mutator = summary("update", containingType: "MysteryType")
        #expect(LiftedTransformation.lift(mutator, carrierKindResolver: resolver) == nil)
    }

    @Test("Empty struct carrier (no stored members) is admitted")
    func emptyStructAdmits() {
        let resolver = CarrierKindResolver(typeDecls: [decl("Marker", .struct)])
        let mutator = summary("touch", containingType: "Marker")
        #expect(LiftedTransformation.lift(mutator, carrierKindResolver: resolver) != nil)
    }

    @Test("Pure enum carrier is admitted")
    func enumCarrierAdmits() {
        let resolver = CarrierKindResolver(typeDecls: [decl("State", .enum)])
        let mutator = summary("advance", containingType: "State")
        #expect(LiftedTransformation.lift(mutator, carrierKindResolver: resolver) != nil)
    }

    // MARK: - Shadow form

    @Test("Lifted return type is the carrier")
    func liftedReturnsCarrier() throws {
        let resolver = valueSemanticResolver()
        let lifted = try #require(LiftedTransformation.lift(
            summary("touch"),
            carrierKindResolver: resolver
        ))
        #expect(lifted.liftedReturnType == "Counter")
    }

    @Test("Lifted parameters prepend the implicit-self binding")
    func liftedPrependsSelf() throws {
        let resolver = valueSemanticResolver()
        let lifted = try #require(LiftedTransformation.lift(
            summary("increment", params: [(label: "by", type: "Int")]),
            carrierKindResolver: resolver
        ))
        #expect(lifted.liftedParameters.count == 2)
        let selfBinding = lifted.liftedParameters[0]
        #expect(selfBinding.label == nil)
        #expect(selfBinding.internalName == "self")
        #expect(selfBinding.typeText == "Counter")
        #expect(selfBinding.isInout == false)
        let original = lifted.liftedParameters[1]
        #expect(original.label == "by")
        #expect(original.typeText == "Int")
    }

    @Test("No-param mutating method lifts to a single-self parameter list")
    func noParamLiftIsUnary() throws {
        let resolver = valueSemanticResolver()
        let lifted = try #require(LiftedTransformation.lift(
            summary("touch"),
            carrierKindResolver: resolver
        ))
        #expect(lifted.liftedParameters.count == 1)
        #expect(lifted.liftedParameters[0].typeText == "Counter")
    }

    @Test("Param-matches-carrier mutating method lifts to a binary self+other parameter list")
    func paramMatchesCarrierLiftIsBinary() throws {
        // Worked example: `mutating func formUnion(_ other: Counter)` lifts
        // to `(Counter, Counter) -> Counter`.
        let resolver = valueSemanticResolver()
        let lifted = try #require(LiftedTransformation.lift(
            summary("formUnion", params: [(label: nil, type: "Counter")]),
            carrierKindResolver: resolver
        ))
        #expect(lifted.liftedParameters.count == 2)
        #expect(lifted.liftedParameters[0].typeText == "Counter")
        #expect(lifted.liftedParameters[1].typeText == "Counter")
    }

    // MARK: - Rationale

    @Test("Rationale names the carrier + method + soundness precondition")
    func rationaleRenders() throws {
        let resolver = valueSemanticResolver()
        let lifted = try #require(LiftedTransformation.lift(
            summary("increment", params: [(label: "by", type: "Int")]),
            carrierKindResolver: resolver
        ))
        #expect(lifted.rationale.contains("mutating func Counter.increment(by:)"))
        #expect(lifted.rationale.contains("value semantics"))
        #expect(lifted.rationale.contains("var copy = original"))
    }

    @Test("Rationale handles no-label parameter list correctly")
    func rationaleHandlesUnlabeledParams() throws {
        let resolver = valueSemanticResolver()
        let lifted = try #require(LiftedTransformation.lift(
            summary("absorb", params: [(label: nil, type: "Counter")]),
            carrierKindResolver: resolver
        ))
        #expect(lifted.rationale.contains("Counter.absorb(_:)"))
    }
}

@Suite("LiftedTransformation — V1.19.A corpus-wide derive() + signal kind")
struct LiftedTransformationDeriveTests {

    private func summary(
        _ name: String,
        params: [(label: String?, type: String)] = [],
        returnType: String? = "Void",
        isMutating: Bool = true,
        containingType: String? = "Counter",
        line: Int = 1,
        file: String = "Test.swift"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params.enumerated().map { index, parameter in
                Parameter(
                    label: parameter.label,
                    internalName: "p\(index)",
                    typeText: parameter.type,
                    isInout: false
                )
            },
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: isMutating,
            isStatic: false,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: containingType,
            bodySignals: .empty
        )
    }

    private func valueSemanticResolver(carrier: String = "Counter") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "value", typeName: "Int")]
            )
        ])
    }

    @Test("derive() returns lifts for every value-semantic mutating summary")
    func deriveReturnsAdmittedLifts() {
        let summaries = [
            summary("touch"),
            summary("increment", params: [(label: "by", type: "Int")]),
            summary("snapshot", returnType: "Int", isMutating: false),
            summary("classMethod", containingType: "Service")
        ]
        // Mix value-semantic resolver with one class TypeDecl so the
        // class-containing mutating summary classifies as referenceType.
        let mixedResolver = CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: "Counter",
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "value", typeName: "Int")]
            ),
            TypeDecl(
                name: "Service",
                kind: TypeDecl.Kind.class,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1)
            )
        ])
        let lifts = LiftedTransformation.derive(
            from: summaries,
            carrierKindResolver: mixedResolver
        )
        // Two admitted: touch + increment; snapshot is non-mutating;
        // classMethod has reference-type carrier.
        #expect(lifts.count == 2)
        #expect(lifts.contains { $0.originalSummary.name == "touch" })
        #expect(lifts.contains { $0.originalSummary.name == "increment" })
    }

    @Test("derive() returns empty list when the corpus has no admissible mutators")
    func deriveEmptyOnEmptyAdmission() {
        let resolver = valueSemanticResolver()
        let summaries = [
            summary("snapshot", returnType: "Int", isMutating: false),
            summary("topLevel", containingType: nil)
        ]
        #expect(LiftedTransformation.derive(from: summaries, carrierKindResolver: resolver).isEmpty)
    }

    @Test("derive() returns lifts in source-order (file then line)")
    func deriveIsSourceOrdered() {
        let resolver = valueSemanticResolver()
        let summaries = [
            summary("late", line: 60),
            summary("early", line: 10),
            summary("middle", line: 30)
        ]
        let lifts = LiftedTransformation.derive(
            from: summaries,
            carrierKindResolver: resolver
        )
        #expect(lifts.map(\.originalSummary.name) == ["early", "middle", "late"])
    }

    @Test("derive() is stable across files in alphabetical path order")
    func deriveStableAcrossFiles() {
        let resolver = valueSemanticResolver()
        let summaries = [
            summary("zMethod", line: 10, file: "Z.swift"),
            summary("aMethod", line: 100, file: "A.swift")
        ]
        let lifts = LiftedTransformation.derive(
            from: summaries,
            carrierKindResolver: resolver
        )
        #expect(lifts.map(\.originalSummary.name) == ["aMethod", "zMethod"])
    }

    @Test("Signal.Kind.liftedFromMutation case exists and renders +10 detail line")
    func liftedFromMutationSignal() {
        let signal = Signal(
            kind: .liftedFromMutation,
            weight: 10,
            detail: "Lifted from mutating method"
        )
        #expect(signal.kind == .liftedFromMutation)
        #expect(signal.weight == 10)
        #expect(signal.formattedLine.contains("(+10)"))
    }
}
