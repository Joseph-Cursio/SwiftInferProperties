import PropertyLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

/// V1.22.A — BucketIterator name extension on V1.21.A's
/// `iteratorProtocolCarrierVeto`. Direct cycle-18 finding closure
/// (3 surviving OC `_HashTable.BucketIterator.*` picks at v1.21 used
/// non-curated method names + carrier ending in `.BucketIterator`,
/// not `.Iterator`).
///
/// Two extensions:
///
/// 1. `iteratorMethodNames` curated set adds `findNext` +
///    `advanceToNextUnoccupiedBucket` (the two cycle-18 method names).
/// 2. Carrier-name fallback rule extends `hasSuffix(".Iterator")` to
///    `hasSuffix("Iterator")` (without the dot), catching
///    `BucketIterator`, `HashIterator`, `MyArrayIterator`, etc.
///
/// The joint match (carrier-name + curated-method-name) is preserved
/// from V1.21.A — false-positive risk on user-code Iterator-named types
/// without state-advancing semantics is bounded by the curated method
/// name requirement.
@Suite("IdempotenceTemplate — V1.22.A BucketIterator name extension")
struct IdempotenceTemplateBucketIteratorTests {

    private func summary(
        _ name: String,
        carrier: String
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    private func valueSemanticResolver(carrier: String) -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "index", typeName: "Int")]
            )
        ])
    }

    private func lifted(method: String, carrier: String) -> LiftedTransformation {
        LiftedTransformation.lift(
            summary(method, carrier: carrier),
            carrierKindResolver: valueSemanticResolver(carrier: carrier)
        )!
    }

    // MARK: - Curated method-name extension

    @Test("'findNext' is now in the curated iteratorMethodNames set")
    func findNextInCuratedSet() {
        #expect(IdempotenceTemplate.iteratorMethodNames.contains("findNext"))
    }

    @Test("'advanceToNextUnoccupiedBucket' is now in the curated iteratorMethodNames set")
    func advanceToNextInCuratedSet() {
        #expect(IdempotenceTemplate.iteratorMethodNames.contains("advanceToNextUnoccupiedBucket"))
    }

    @Test("Pre-V1.22.A curated names still in set (next, advance, nextState, step)")
    func preV122NamesPreserved() {
        let original = ["next", "advance", "nextState", "step"]
        for name in original {
            #expect(IdempotenceTemplate.iteratorMethodNames.contains(name))
        }
    }

    // MARK: - Carrier-name suffix extension

    @Test("`BucketIterator` carrier + `advance` method fires veto via name fallback")
    func bucketIteratorAdvanceVetoes() {
        let lift = lifted(method: "advance", carrier: "_HashTable.BucketIterator")
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: [:]
        )
        let veto = try! #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("Iterator-shape name"))
    }

    @Test("`BucketIterator` carrier + `findNext` method fires veto (cycle-18 finding case)")
    func bucketIteratorFindNextVetoes() {
        let lift = lifted(method: "findNext", carrier: "_HashTable.BucketIterator")
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: [:]
        )
        #expect(signal?.isVeto == true)
    }

    @Test("`BucketIterator` carrier + `advanceToNextUnoccupiedBucket` fires veto")
    func bucketIteratorAdvanceToNextVetoes() {
        let lift = lifted(method: "advanceToNextUnoccupiedBucket", carrier: "_HashTable.BucketIterator")
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: [:]
        )
        #expect(signal?.isVeto == true)
    }

    // MARK: - Joint-match guardrail (false-positive control)

    @Test("`BucketIterator` carrier + non-curated method ('removeAll') does NOT veto")
    func bucketIteratorNonCuratedMethodPreserves() {
        let lift = lifted(method: "removeAll", carrier: "_HashTable.BucketIterator")
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: [:]
        )
        #expect(signal == nil, "Joint match must require curated method name")
    }

    @Test("Non-Iterator carrier + curated method does NOT veto")
    func nonIteratorCarrierWithCuratedMethodPreserves() {
        // 'next' is in curated names but 'Bag' isn't an Iterator-shape carrier.
        let lift = lifted(method: "next", carrier: "Bag")
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: [:]
        )
        #expect(signal == nil)
    }

    // MARK: - Other Iterator-suffix carriers

    @Test("`HashIterator` carrier + `next` method fires veto")
    func hashIteratorVetoes() {
        let lift = lifted(method: "next", carrier: "HashIterator")
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: [:]
        )
        #expect(signal?.isVeto == true)
    }

    @Test("Pre-V1.22.A patterns (bare `Iterator`, `*.Iterator`) still veto")
    func preV122PatternsPreserved() {
        for carrier in ["Iterator", "Foo.Iterator", "Bar.Baz.Iterator"] {
            let lift = lifted(method: "next", carrier: carrier)
            let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
                for: lift,
                inheritedTypesByName: [:]
            )
            #expect(signal?.isVeto == true, "Pre-V1.22.A carrier '\(carrier)' should still veto")
        }
    }
}
