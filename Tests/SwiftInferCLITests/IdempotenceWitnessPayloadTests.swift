import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// Regression coverage for the payload-bearing idempotence-witness build
// failure: the reducer emitter used to emit the bare `.select` for a
// `case select(Int)` witness (which fails to compile in `reduce(into:action:)`).
// The witness payload is now synthesized from the Action alphabet (x-curried:
// the same canned value in both applications). These are FAST string tests —
// the gap that hid the bug was that no unit test crossed "idempotence witness"
// × "payload-bearing case" (and string tests don't compile the stub).
@Suite("Idempotence witness payload synthesis")
struct IdempotenceWitnessPayloadTests {

    private let now = Date(timeIntervalSince1970: 0)

    private func tcaCandidate() -> ReducerCandidate {
        ReducerCandidate(
            location: "F.swift:1",
            enclosingTypeName: "Feature",
            functionName: "body",
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: "Feature.State",
            actionTypeName: "Feature.Action",
            carrierKind: .tca,
            // Non-empty constructible cases so the `.tca` validate gate passes;
            // the generator uses these, the witness synthesis uses the alphabet.
            actionCases: [
                ActionCaseInfo(name: "reset", payloadTypes: []),
                ActionCaseInfo(name: "select", payloadTypes: ["Int"])
            ]
        )
    }

    private func idempotenceInvariant(predicate: String) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .idempotence,
            reducerQualifiedName: "Feature.body",
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .idempotence,
            reducerQualifiedName: "Feature.body",
            reducerLocation: "F.swift:1",
            stateTypeName: "Feature.State",
            actionTypeName: "Feature.Action",
            predicate: predicate,
            score: 80,
            tier: .strong,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: now
        )
    }

    private func emit(witnessPredicate: String, alphabet: [ActionCaseSpec]) throws -> String {
        try ActionSequenceStubEmitter.emit(ActionSequenceStubEmitter.Inputs(
            candidate: tcaCandidate(),
            userModuleName: "Feature",
            invariant: idempotenceInvariant(predicate: witnessPredicate),
            actionAlphabet: alphabet
        ))
    }

    @Test("Payload-bearing witness synthesizes the payload (the fix)")
    func payloadBearingWitnessSynthesized() throws {
        let alphabet = [ActionCaseSpec(name: "select", parameters: [ActionParam(label: nil, type: "Int")])]
        let source = try emit(witnessPredicate: ".select", alphabet: alphabet)
        // The witness is applied with a canned Int, not the bare (uncompilable) `.select`.
        #expect(source.contains("action: .select(0)"))
        #expect(!source.contains("action: .select)"))
    }

    @Test("Labeled payload keeps the label in the synthesized witness")
    func labeledPayloadWitness() throws {
        let param = ActionParam(label: "value", type: "Int")
        let alphabet = [ActionCaseSpec(name: "setColor", parameters: [param])]
        let source = try emit(witnessPredicate: ".setColor", alphabet: alphabet)
        #expect(source.contains("action: .setColor(value: 0)"))
    }

    @Test("Payload-free witness is emitted bare (unchanged)")
    func payloadFreeWitnessUnchanged() throws {
        let source = try emit(
            witnessPredicate: ".reset",
            alphabet: [ActionCaseSpec(name: "reset", parameters: [])]
        )
        #expect(source.contains("action: .reset)"))
    }

    @Test("Non-defaultable payload falls back to the bare predicate (no regression)")
    func nonDefaultablePayloadFallback() throws {
        let param = ActionParam(label: nil, type: "Color")
        let alphabet = [ActionCaseSpec(name: "select", parameters: [param])]
        let source = try emit(witnessPredicate: ".select", alphabet: alphabet)
        // Color isn't defaultable → unchanged bare `.select` (today's
        // build-fails→coverage-pending behavior; a pre-build gate is a follow-up).
        #expect(source.contains("action: .select)"))
    }

    @Test("Empty alphabet leaves the witness bare (no regression for callers without an alphabet)")
    func emptyAlphabetFallback() throws {
        let source = try emit(witnessPredicate: ".select", alphabet: [])
        #expect(source.contains("action: .select)"))
    }
}
