import Foundation
@testable import SwiftInferCore
import Testing

// V2.0 M8.B — body-purity population from `ReducerPurityAnalyzer`.
// Extension-grouped so the main struct stays under SwiftLint's
// type_body_length cap.
extension ReducerDiscovererTests {

    @Test("M8.B — pure body returns purity: .pure")
    func purityPureForCleanBody() {
        let source = """
        func reduce(_ state: AppState, _ action: AppAction) -> AppState {
            return state
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].purity == .pure)
    }

    @Test("M8.B — body with Effect reference returns purity: .effectBearing")
    func purityEffectBearingForEffectReference() {
        let source = """
        func reduce(_ state: AppState, _ action: AppAction) -> (AppState, Effect<AppAction>) {
            return (state, Effect.run { _ in })
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].purity == .effectBearing)
    }

    @Test("M8.B — body that writes to a static var returns purity: .hiddenMutability")
    func purityHiddenMutabilityForStaticWrite() {
        let source = """
        func reduce(_ state: AppState, _ action: AppAction) -> AppState {
            Self.counter += 1
            return state
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].purity == .hiddenMutability)
    }
}
