import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — the MVVM verify→evidence bridge (the discover↔verify join).
@Suite("ViewModelVerifyEvidence (prototype)")
struct ViewModelVerifyEvidenceTests {

    private func suggestion() -> InteractionInvariantSuggestion {
        InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: "idempotence::VM::selectAll()"),
            family: .idempotence,
            reducerQualifiedName: "VM",
            reducerLocation: "VM.swift:1",
            stateTypeName: "VM",
            actionTypeName: "VM",
            predicate: "selectAll() is idempotent",
            score: 30,
            tier: .possible,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("maps the verify outcome to evidence keyed to the suggestion identity")
    func mapsOutcomeToEvidence() {
        let pass = ViewModelVerifyEvidence.evidence(
            for: suggestion(),
            outcome: .bothPass(defaultTrials: 1, edgeTrials: 0, edgeSampled: 0)
        )
        #expect(pass.identityHash == suggestion().identity.normalized)
        #expect(pass.outcome == .measuredBothPass)
        #expect(pass.template == "idempotence")
        #expect(pass.excludedActionCount == 0)

        let fail = ViewModelVerifyEvidence.evidence(
            for: suggestion(),
            outcome: .defaultFails(
                trial: 0, input: "", forwardResult: "",
                inverseResult: "", shrunk: nil, shrinkSteps: 0
            )
        )
        #expect(fail.outcome == .measuredDefaultFails)
    }
}
