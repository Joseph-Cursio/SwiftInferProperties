import PropertyLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

/// V1.27.A — Sequence-conformance fallback path on V1.21.A's
/// `iteratorProtocolCarrierVeto`. Direct cycle-23 finding closure: Algo
/// idempotence-lifted picks measured REJECT on Sequence-conforming
/// carriers that expose `next()`/`advance()` directly without explicit
/// IteratorProtocol conformance.
@Suite("IdempotenceTemplate — V1.27.A Sequence-conformance fallback")
struct IdempotenceTemplateSequenceConformanceTests {

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
                inheritedTypes: ["Sequence"],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "base", typeName: "[Int]")]
            )
        ])
    }

    private func lifted(method: String, carrier: String) -> LiftedTransformation {
        LiftedTransformation.lift(
            summary(method, carrier: carrier),
            carrierKindResolver: valueSemanticResolver(carrier: carrier)
        )!
    }

    @Test("Sequence-conforming carrier + 'next' fires veto (cycle-23 case)")
    func sequenceCarrierNextFires() {
        let lift = lifted(method: "next", carrier: "ChainSequence")
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lift,
            inheritedTypesByName: ["ChainSequence": ["Sequence"]]
        )
        let veto = try! #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("Sequence"))
    }

    @Test("Sequence + 'advance' fires veto")
    func sequenceCarrierAdvanceFires() {
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lifted(method: "advance", carrier: "ChainSequence"),
            inheritedTypesByName: ["ChainSequence": ["Sequence"]]
        )
        #expect(signal?.isVeto == true)
    }

    @Test("Sequence + non-curated method ('removeAll') does NOT fire")
    func sequenceNonCuratedMethodDoesNotFire() {
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lifted(method: "removeAll", carrier: "ChainSequence"),
            inheritedTypesByName: ["ChainSequence": ["Sequence"]]
        )
        #expect(signal == nil, "Joint match required: Sequence + curated method")
    }

    @Test("Non-Sequence carrier + 'next' falls through to name-fallback path")
    func nonSequenceFallsThroughToNamePath() {
        // Carrier 'OrderedDictionary' isn't IteratorProtocol or Sequence;
        // but method 'next' is curated. Falls through to V1.21.A name-
        // fallback which requires `*Iterator` carrier-suffix — also doesn't
        // match here. So no veto fires.
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lifted(method: "next", carrier: "OrderedDictionary"),
            inheritedTypesByName: [:]
        )
        #expect(signal == nil)
    }

    @Test("V1.21.A IteratorProtocol path still fires (Sequence path doesn't interfere)")
    func iteratorProtocolPathStillFires() {
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lifted(method: "next", carrier: "Iterator"),
            inheritedTypesByName: ["Iterator": ["IteratorProtocol"]]
        )
        let veto = try! #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("conforms to IteratorProtocol"))
    }

    @Test("Both Sequence + IteratorProtocol → fires (IteratorProtocol path wins; detail prefers IteratorProtocol)")
    func bothProtocolsCarrierFires() {
        let signal = IdempotenceTemplate.iteratorProtocolCarrierVeto(
            for: lifted(method: "next", carrier: "MyIter"),
            inheritedTypesByName: ["MyIter": ["IteratorProtocol", "Sequence"]]
        )
        let veto = try! #require(signal)
        #expect(veto.isVeto)
        // IteratorProtocol path is checked first; its detail string fires.
        #expect(veto.detail.contains("IteratorProtocol"))
    }
}
