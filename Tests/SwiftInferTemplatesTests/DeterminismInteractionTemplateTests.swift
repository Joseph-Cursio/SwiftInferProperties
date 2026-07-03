import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("DeterminismInteractionTemplate — Phase 2 Redux production seam")
struct DeterminismInteractionTemplateTests {

    private func candidate(
        carrierKind: ReducerCarrierKind = .elmStyle,
        purity: ReducerPurity = .pure,
        stateTypeName: String = "AppState",
        actionTypeName: String = "AppAction"
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/App/Reducer.swift:5",
            enclosingTypeName: nil,
            functionName: "reduce",
            signatureShape: .stateActionReturnsState,
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName,
            carrierKind: carrierKind,
            purity: purity
        )
    }

    private let firstSeen = ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!

    @Test("emits exactly one determinism suggestion for every carrier, incl. TCA")
    func emitsOneForEveryCarrier() {
        for carrier in ReducerCarrierKind.allCases {
            let out = DeterminismInteractionTemplate.analyze(
                candidate: candidate(carrierKind: carrier), firstSeenAt: firstSeen
            )
            #expect(out.count == 1, "\(carrier) should emit one determinism suggestion")
            #expect(out.first?.family == .determinism)
        }
    }

    @Test("TCA now surfaces determinism (dependency-pinned) — the real-world audience")
    func includesTCA() {
        let out = DeterminismInteractionTemplate.analyze(
            candidate: candidate(carrierKind: .tca), firstSeenAt: firstSeen
        )
        #expect(out.count == 1)
        #expect(out.first?.family == .determinism)
        // The why-suggested prose reflects the TCA dependency-pinning framing.
        #expect(out.first?.whySuggested.contains { $0.contains("@Dependency") } == true)
    }

    @Test("ships at .possible (score 30) — default for a new family per §3.5")
    func shipsAtPossible() {
        let suggestion = DeterminismInteractionTemplate.analyze(
            candidate: candidate(), firstSeenAt: firstSeen
        ).first
        #expect(suggestion?.score == 30)
        #expect(suggestion?.tier == .possible)
    }

    @Test("suggestion is self-describing: carrier + purity in why-suggested, Date/UUID caveat")
    func explainability() {
        let suggestion = DeterminismInteractionTemplate.analyze(
            candidate: candidate(carrierKind: .reSwift, purity: .effectBearing),
            firstSeenAt: firstSeen
        ).first
        #expect(suggestion?.whySuggested.contains { $0.contains("reswift") } == true)
        #expect(suggestion?.whySuggested.contains { $0.contains("effect-bearing") } == true)
        #expect(suggestion?.whyMightBeWrong.contains { $0.contains("Date()") } == true)
    }

    @Test("identity is stable + distinct per reducer (family, name, fixed predicate)")
    func identityStableAndDistinct() {
        let one = DeterminismInteractionTemplate.analyze(
            candidate: candidate(stateTypeName: "AState"), firstSeenAt: firstSeen
        ).first
        let again = DeterminismInteractionTemplate.analyze(
            candidate: candidate(stateTypeName: "AState"), firstSeenAt: firstSeen
        ).first
        #expect(one?.identity == again?.identity)
        // The predicate is fixed, so identity varies only by reducer name.
        #expect(one?.predicate == "reduce(s, a) == reduce(s, a)")
    }
}
