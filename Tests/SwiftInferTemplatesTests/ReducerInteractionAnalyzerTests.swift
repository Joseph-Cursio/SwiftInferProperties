import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("ReducerInteractionAnalyzer — Redux-distinctive candidate invariants")
struct ReducerInteractionAnalyzerTests {

    private func candidate(
        carrierKind: ReducerCarrierKind,
        purity: ReducerPurity = .pure,
        actionCases: [ActionCaseInfo] = [],
        stateTypeName: String = "AppState",
        actionTypeName: String = "AppAction",
        functionName: String = "reduce"
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/Feature.swift:10",
            enclosingTypeName: nil,
            functionName: functionName,
            signatureShape: .stateActionReturnsState,
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName,
            carrierKind: carrierKind,
            purity: purity,
            actionCases: actionCases
        )
    }

    // MARK: - Paradigm gate

    @Test
    func tcaReducerSurfacesNoDistinctiveCandidates() {
        // TCA has its own richer invariant story — excluded here by design.
        let result = ReducerInteractionAnalyzer.analyze(candidate(carrierKind: .tca))
        #expect(result.isEmpty)
    }

    @Test
    func everyNonTCAFamilyIsTreatedAsRedux() {
        for carrier in ReducerCarrierKind.allCases where carrier != .tca {
            #expect(carrier.isReduxFamily, "\(carrier) should be a redux-family carrier")
            let result = ReducerInteractionAnalyzer.analyze(candidate(carrierKind: carrier))
            #expect(result.isEmpty == false, "\(carrier) should surface candidates")
        }
    }

    // MARK: - Determinism

    @Test
    func reduxReducerAlwaysSurfacesDeterminism() {
        // Determinism fires regardless of the static purity label — the purity
        // analyzer doesn't check Date()/UUID()/random(), so it's genuinely
        // unsettled by static means.
        for purity in ReducerPurity.allCases {
            let result = ReducerInteractionAnalyzer.analyze(
                candidate(carrierKind: .elmStyle, purity: purity, actionCases: [ActionCaseInfo(name: "tap")])
            )
            #expect(result.contains { $0.kind == .determinism },
                    "determinism should surface for purity \(purity.rawValue)")
        }
    }

    @Test
    func determinismSubjectsAreStateAndAction() {
        let result = ReducerInteractionAnalyzer.analyze(
            candidate(carrierKind: .elmStyle, actionCases: [ActionCaseInfo(name: "tap")])
        )
        let determinism = result.first { $0.kind == .determinism }
        #expect(determinism?.subjects == ["AppState", "AppAction"])
    }

    @Test
    func impuritySignalSharpensTheDeterminismRationale() {
        let pureResult = ReducerInteractionAnalyzer.analyze(
            candidate(carrierKind: .elmStyle, purity: .pure, actionCases: [ActionCaseInfo(name: "tap")])
        )
        let impureResult = ReducerInteractionAnalyzer.analyze(
            candidate(carrierKind: .elmStyle, purity: .hiddenMutability, actionCases: [ActionCaseInfo(name: "tap")])
        )
        let pure = pureResult.first { $0.kind == .determinism }
        let impure = impureResult.first { $0.kind == .determinism }
        #expect(pure?.rationale.contains("hidden-mutability") == false)
        #expect(impure?.rationale.contains("hidden-mutability") == true)
    }

    // MARK: - Unknown-action-is-no-op (open alphabets only)

    @Test
    func closedEnumAlphabetSuppressesUnknownActionNoOp() {
        // A statically-resolved closed enum is exhaustive — no unknown action
        // is representable, so the invariant would be a tautology.
        let result = ReducerInteractionAnalyzer.analyze(
            candidate(carrierKind: .elmStyle, actionCases: [
                ActionCaseInfo(name: "increment"), ActionCaseInfo(name: "decrement")
            ])
        )
        #expect(result.contains { $0.kind == .unknownActionIsNoOp } == false)
    }

    @Test
    func openAlphabetSurfacesUnknownActionNoOp() {
        // No resolved cases (a protocol `Action` à la ReSwift) → open alphabet.
        let result = ReducerInteractionAnalyzer.analyze(
            candidate(carrierKind: .reSwift, actionCases: [])
        )
        let noOp = result.first { $0.kind == .unknownActionIsNoOp }
        #expect(noOp != nil)
        #expect(noOp?.subjects == ["AppAction"])
    }

    @Test
    func openReduxReducerSurfacesBothDistinctiveCandidates() {
        let result = ReducerInteractionAnalyzer.analyze(
            candidate(carrierKind: .reSwift, actionCases: [])
        )
        let kinds = result.map(\.kind)
        #expect(Set(kinds) == [.determinism, .unknownActionIsNoOp])
    }
}
