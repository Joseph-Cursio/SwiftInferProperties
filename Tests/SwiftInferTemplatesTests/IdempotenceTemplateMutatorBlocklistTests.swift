import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.24.B — explicit non-idempotent mutator-name veto on idempotence-
/// lifted. Direct cycle-20 finding closure (V1.20.C 4/4 reject on OC
/// reverse/removeFirst/removeLast lifted picks).
///
/// Distinct from V1.21.A's `iteratorProtocolCarrierVeto`: V1.24.B fires
/// on ANY value-semantic carrier (no protocol-conformance requirement);
/// V1.21.A fires only on IteratorProtocol-conforming or Iterator-named
/// carriers. The two vetoes target structurally-distinct classes.
@Suite("IdempotenceTemplate — V1.24.B mutator-blocklist veto on idempotence-lifted")
struct IdempotenceTemplateMutatorBlocklistTests {

    private func summary(
        _ name: String,
        carrier: String = "OrderedDictionary"
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

    private func valueSemanticResolver(carrier: String = "OrderedDictionary") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "elements", typeName: "[Int]")]
            )
        ])
    }

    private func lifted(method: String, carrier: String = "OrderedDictionary") -> LiftedTransformation {
        LiftedTransformation.lift(
            summary(method, carrier: carrier),
            carrierKindResolver: valueSemanticResolver(carrier: carrier)
        )!
    }

    // MARK: - Curated set membership

    @Test("MutatorBlockedFromIdempotence.curated includes cycle-20 picks (reverse, removeFirst, removeLast)")
    func curatedIncludesCycle20Picks() {
        for name in ["reverse", "removeFirst", "removeLast"] {
            #expect(MutatorBlockedFromIdempotence.curated.contains(name))
        }
    }

    @Test("MutatorBlockedFromIdempotence.curated includes future-corpora variants (pop*/drop*)")
    func curatedIncludesPopAndDrop() {
        for name in ["popFirst", "popLast", "dropFirst", "dropLast"] {
            #expect(MutatorBlockedFromIdempotence.curated.contains(name))
        }
    }

    @Test("MutatorBlockedFromIdempotence.curated includes involutions (negate/toggle/twosComplement — BigInt dogfood)")
    func curatedIncludesInvolutions() {
        // Self-inverse mutators (`f(f(s)) == s`) are non-idempotent, like
        // `reverse`. `attaswift/BigInt` surfaced real `negate()` +
        // `twosComplement()` lifted-idempotence false positives at Likely.
        for name in ["negate", "toggle", "invert", "complement", "twosComplement"] {
            #expect(MutatorBlockedFromIdempotence.curated.contains(name))
        }
    }

    // MARK: - Veto fires on curated names (cycle-20 cases)

    @Test("'reverse' on OrderedDictionary fires veto (cycle-20 #41 case)")
    func reverseOnOrderedDictionaryVetoes() throws {
        let signal = IdempotenceTemplate.mutatorBlocklistVeto(forLifted: lifted(method: "reverse"))
        let veto = try #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("'reverse'"))
    }

    @Test("'removeFirst' on OrderedDictionary fires veto (cycle-20 #42 case)")
    func removeFirstVetoes() {
        let signal = IdempotenceTemplate.mutatorBlocklistVeto(forLifted: lifted(method: "removeFirst"))
        #expect(signal?.isVeto == true)
    }

    @Test("'removeLast' on OrderedDictionary fires veto (cycle-20 #43 case)")
    func removeLastVetoes() {
        let signal = IdempotenceTemplate.mutatorBlocklistVeto(forLifted: lifted(method: "removeLast"))
        #expect(signal?.isVeto == true)
    }

    @Test("All curated names fire veto on a value-semantic carrier")
    func allCuratedFireVeto() {
        for name in MutatorBlockedFromIdempotence.curated {
            let signal = IdempotenceTemplate.mutatorBlocklistVeto(forLifted: lifted(method: name))
            #expect(signal?.isVeto == true, "'\(name)' should veto")
        }
    }

    // MARK: - Veto does NOT fire on non-curated names

    @Test("'sort' on OrderedDictionary does NOT fire veto (sort IS idempotent)")
    func sortDoesNotVeto() {
        let signal = IdempotenceTemplate.mutatorBlocklistVeto(forLifted: lifted(method: "sort"))
        #expect(signal == nil, "sort is idempotent (fixed-point); must not veto")
    }

    @Test("'normalize' does not veto")
    func normalizeDoesNotVeto() {
        let signal = IdempotenceTemplate.mutatorBlocklistVeto(forLifted: lifted(method: "normalize"))
        #expect(signal == nil)
    }

    @Test("Carrier-protocol-agnostic: fires on OrderedDictionary (NOT IteratorProtocol)")
    func firesOnNonIteratorCarrier() {
        // V1.21.A wouldn't fire here (OrderedDictionary doesn't conform to
        // IteratorProtocol and doesn't have an Iterator-suffix name).
        // V1.24.B DOES fire because the structural argument is about the
        // method name semantics, not the carrier's protocol stack.
        let signal = IdempotenceTemplate.mutatorBlocklistVeto(
            forLifted: lifted(method: "reverse", carrier: "OrderedDictionary")
        )
        #expect(signal?.isVeto == true)
    }

    // MARK: - End-to-end suggest()

    @Test("End-to-end: OrderedDictionary.reverse() lifted-idempotence is suppressed at v1.24.B")
    func endToEndReverseSuppressed() {
        let suggestion = IdempotenceTemplate.suggest(
            forLifted: lifted(method: "reverse"),
            carrierKindResolver: valueSemanticResolver()
        )
        #expect(suggestion == nil, "V1.24.B should suppress reverse-class lifted-idempotence")
    }

    @Test("End-to-end: OrderedDictionary.sort() lifted-idempotence still surfaces (sort IS idempotent)")
    func endToEndSortStillSurfaces() {
        let suggestion = IdempotenceTemplate.suggest(
            forLifted: lifted(method: "sort"),
            carrierKindResolver: valueSemanticResolver()
        )
        #expect(suggestion != nil, "V1.24.B must NOT suppress idempotent sort")
    }
}
