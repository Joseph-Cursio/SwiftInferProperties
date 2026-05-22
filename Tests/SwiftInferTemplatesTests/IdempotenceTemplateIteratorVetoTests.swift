import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.21.A — IteratorProtocol carrier veto on lifted-idempotence
/// suggestions. Direct cycle-17 finding closure (4/4 reject on Iterator-
/// shape picks). Two detection paths under test:
///
/// 1. Primary: textual conformance via `inheritedTypesByName` — fires when
///    the corpus index records `Carrier → {..., "IteratorProtocol", ...}`.
/// 2. Name fallback: carrier name `"Iterator"` or `"X.Iterator"` AND
///    method name in curated `iteratorMethodNames`.
@Suite("IdempotenceTemplate — V1.21.A IteratorProtocol carrier veto")
struct IdempotenceTemplateIteratorVetoTests {

    // MARK: - Helpers

    private func summary(
        _ name: String,
        carrier: String,
        params: [(String?, String)] = [],
        line: Int = 1
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params.enumerated().map { index, spec in
                Parameter(
                    label: spec.0,
                    internalName: "p\(index)",
                    typeText: spec.1,
                    isInout: false
                )
            },
            returnTypeText: "Void",
            isThrows: false,
            isAsync: false,
            isMutating: true,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: line, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    private func valueSemanticResolver(carrier: String) -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: ["IteratorProtocol"],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "index", typeName: "Int")]
            )
        ])
    }

    private func lifted(
        method: String,
        carrier: String,
        params: [(String?, String)] = []
    ) -> LiftedTransformation {
        let resolver = valueSemanticResolver(carrier: carrier)
        return LiftedTransformation.lift(
            summary(method, carrier: carrier, params: params),
            carrierKindResolver: resolver
        )!
    }

    // MARK: - Primary path (textual conformance)

    @Test("Carrier conforming to IteratorProtocol vetoes lifted idempotence (Score → Suppressed)")
    func conformanceVetoFires() throws {
        let lift = lifted(method: "next", carrier: "AdjacentPairsIterator")
        let inheritedIndex: [String: Set<String>] = [
            "AdjacentPairsIterator": ["IteratorProtocol"]
        ]
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: inheritedIndex
        )
        let veto = try #require(signal)
        #expect(veto.isVeto)
        #expect(veto.kind == .protocolCoveredProperty)
        #expect(veto.detail.contains("conforms to IteratorProtocol"))
        #expect(veto.detail.contains("next()"))
    }

    @Test("Conformance veto strips outermost generic parameters before index lookup")
    func conformanceVetoStripsGenerics() throws {
        // Construct lift directly (bypass resolver gate) — we're testing
        // the veto helper's strip behavior, not the admission gate.
        let summary = self.summary("next", carrier: "Combinations<Base>")
        let lift = LiftedTransformation(
            originalSummary: summary,
            carrier: "Combinations<Base>",
            liftedParameters: [
                Parameter(label: nil, internalName: "self", typeText: "Combinations<Base>", isInout: false)
            ],
            liftedReturnType: "Combinations<Base>",
            rationale: "test"
        )
        // Index keyed by the stripped form ("Combinations") — matches
        // ProtocolCoverageMap.inheritedTypesIndex's posture (V1.5.2
        // strips generics when building the index).
        let inheritedIndex: [String: Set<String>] = [
            "Combinations": ["IteratorProtocol"]
        ]
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: inheritedIndex
        )
        let veto = try #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("conforms to IteratorProtocol"))
    }

    @Test("Carrier without IteratorProtocol conformance does not fire conformance veto")
    func conformanceVetoMissesNonIteratorCarrier() {
        let lift = lifted(method: "removeAll", carrier: "Bag")
        let inheritedIndex: [String: Set<String>] = [
            "Bag": ["Sequence"]
        ]
        // method "removeAll" is not in iteratorMethodNames AND carrier name
        // doesn't end in Iterator, so neither path fires.
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: inheritedIndex
        )
        #expect(signal == nil)
    }

    @Test("Empty inheritedTypesByName index falls through to name fallback")
    func emptyIndexAllowsNameFallback() throws {
        let lift = lifted(method: "advance", carrier: "MyType.Iterator")
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: [:]
        )
        let veto = try #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("Iterator-shape name"))
        #expect(veto.detail.contains("advance"))
    }

    // MARK: - Name fallback path

    @Test("Bare carrier name 'Iterator' + method 'next' fires name fallback veto")
    func nameFallbackOnBareIterator() throws {
        let lift = lifted(method: "next", carrier: "Iterator")
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: [:]
        )
        let veto = try #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("Iterator-shape name"))
    }

    @Test("Nested carrier 'Foo.Iterator' + method 'next' fires name fallback veto")
    func nameFallbackOnNestedIterator() throws {
        let lift = lifted(method: "next", carrier: "AdjacentPairsSequence.Iterator")
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: [:]
        )
        let veto = try #require(signal)
        #expect(veto.isVeto)
    }

    @Test("Name fallback fires on all curated method names: next, advance, nextState, step")
    func nameFallbackCoversAllCuratedMethods() throws {
        for methodName in IdempotenceTemplate.iteratorMethodNames {
            let lift = lifted(method: methodName, carrier: "Iterator")
            let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
                for: lift,
                inheritedTypesByName: [:]
            )
            let veto = try #require(signal, "Expected veto for method '\(methodName)'")
            #expect(veto.isVeto)
        }
    }

    @Test("Iterator-named carrier with non-curated method name does NOT fire name fallback")
    func nameFallbackRequiresCuratedMethodName() {
        // Carrier is Iterator-shaped but method "removeAll" isn't a
        // canonical Iterator-pattern name → name fallback doesn't fire.
        // (Conformance path also doesn't fire since index is empty.)
        let lift = lifted(method: "removeAll", carrier: "MyIterator")
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: [:]
        )
        #expect(signal == nil)
    }

    // Curated method name on non-Iterator-shaped carrier does NOT fire name fallback
    // (no Sequence/IteratorProtocol conformance).
    @Test("Curated method name on non-Iterator carrier does NOT fire name fallback")
    func nameFallbackRequiresIteratorCarrierShape() {
        // Method is "next" but carrier "Bag" isn't IteratorProtocol-conforming,
        // Sequence-conforming (V1.27.A path), or `*Iterator`-suffixed.
        // No veto fires.
        let lift = lifted(method: "next", carrier: "Bag")
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: ["Bag": ["Comparable"]]
        )
        #expect(signal == nil)
    }

    // MARK: - End-to-end interaction with lifted suggest()

    @Test("End-to-end: Iterator-protocol-carrier-with-conformance suppresses lifted-idempotence suggestion")
    func endToEndConformanceSuppression() {
        let lift = lifted(method: "next", carrier: "AdjacentPairsIterator")
        let inheritedIndex: [String: Set<String>] = [
            "AdjacentPairsIterator": ["IteratorProtocol"]
        ]
        let resolver = CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: "AdjacentPairsIterator",
                kind: .struct,
                inheritedTypes: ["IteratorProtocol"],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "index", typeName: "Int")]
            )
        ])
        // Without veto (cycle-17 baseline): 30 type-symmetry + 5 carrier
        // + 10 lifted = 45 → Likely. With V1.21.A veto: Suppressed.
        let suggestion = IdempotenceTemplate.suggest(
            forLifted: lift,
            inheritedTypesByName: inheritedIndex,
            carrierKindResolver: resolver
        )
        #expect(suggestion == nil, "V1.21.A veto should suppress Iterator-protocol-conforming carriers")
    }

    @Test("End-to-end: name-fallback Iterator carrier suppresses lifted-idempotence suggestion")
    func endToEndNameFallbackSuppression() {
        let lift = lifted(method: "advance", carrier: "MyIterator.Iterator")
        let resolver = CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: "MyIterator.Iterator",
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "index", typeName: "Int")]
            )
        ])
        let suggestion = IdempotenceTemplate.suggest(
            forLifted: lift,
            inheritedTypesByName: [:],
            carrierKindResolver: resolver
        )
        #expect(
            suggestion == nil,
            "V1.21.A name fallback should suppress Iterator-shape carriers + curated method names"
        )
    }

    @Test("End-to-end: non-Iterator value-semantic carrier still produces Likely suggestion")
    func endToEndNonIteratorPreserved() throws {
        // Sanity-check: a `removeAll` on a non-Iterator value-semantic struct
        // must still surface (V1.21.A veto must not fire false-positives).
        let resolver = CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: "Bag",
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "items", typeName: "[Int]")]
            )
        ])
        let lift = LiftedTransformation.lift(
            summary("removeAll", carrier: "Bag"),
            carrierKindResolver: resolver
        )!
        let suggestion = IdempotenceTemplate.suggest(
            forLifted: lift,
            carrierKindResolver: resolver
        )
        let result = try #require(suggestion)
        // 30 type-symmetry + 5 carrier + 10 lifted = 45 → Likely.
        #expect(result.score.total == 45)
    }
}
