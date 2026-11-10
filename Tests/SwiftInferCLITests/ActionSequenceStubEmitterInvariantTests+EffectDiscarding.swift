import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// V2.0 M8.A — effect-discarding idempotence-check shape assertions
// for the two effect-bearing signatures. Extension-grouped so the
// parent struct's body stays under SwiftLint's type_body_length cap.
extension ActionSequenceStubEmitterInvariantTests {

    @Test("makeIdempotenceCheck (S, A) -> (S, Effect<A>) — captures + discards effect (M8.A)")
    func makeIdempotenceCheckStateActionReturnsStateAndEffect() {
        let block = ActionSequenceStubEmitter.makeIdempotenceCheck(
            actionExpr: ".tap",
            shape: .stateActionReturnsStateAndEffect,
            reducerCall: "reduce"
        )
        #expect(block.count == 3)
        #expect(block[0] == "let (once, _) = reduce(state, .tap)")
        #expect(block[1] == "let (twice, _) = reduce(once, .tap)")
        #expect(block[2].contains("precondition(once == twice"))
    }

    @Test("makeIdempotenceCheck (inout S, A) -> Effect<A> — captures + discards effect (M8.A)")
    func makeIdempotenceCheckInoutEffect() {
        let block = ActionSequenceStubEmitter.makeIdempotenceCheck(
            actionExpr: ".refresh",
            shape: .inoutStateActionReturnsEffect,
            reducerCall: "reduce"
        )
        #expect(block.count == 5)
        #expect(block[0] == "var once = state")
        #expect(block[1] == "_ = reduce(&once, .refresh)")
        #expect(block[2] == "var twice = once")
        #expect(block[3] == "_ = reduce(&twice, .refresh)")
        #expect(block[4].contains("precondition(once == twice"))
    }
}
