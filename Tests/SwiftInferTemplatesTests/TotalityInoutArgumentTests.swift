import SwiftInferCore
import SwiftInferTemplates
import Testing

/// **An `inout` argument is passed a `var` copy with `&`, not the drawn `let`.**
///
/// `JSONRPCFraming.extractMessages(from buffer: inout Data)` emitted
/// `_ = JSONRPCFraming.extractMessages(from: value)`, which fails with `cannot pass immutable value
/// as inout argument` (SwiftAssist, 2026-09-19 corpus funnel). Totality over a buffer a framer
/// consumes is exactly the fuzz-style law this template exists for, so the fix is to write it,
/// not to decline it.
@Suite("Totality — inout arguments")
struct TotalityInoutArgumentTests {

    private static let seed = SamplingSeed.Value(
        stateA: 0x1234_5678_9ABC_DEF0,
        stateB: 0x0FED_CBA9_8765_4321,
        stateC: 0xAAAA_BBBB_CCCC_DDDD,
        stateD: 0x1111_2222_3333_4444
    )

    @Test("a single inout argument is copied and passed with &")
    func singleInout() {
        let stub = LiftedTestEmitter.total(
            callee: CalleeReference(bareName: "extractMessages", qualifier: "JSONRPCFraming", argumentLabels: ["from"]),
            seed: Self.seed,
            generators: ["Gen<Data>.data()"],
            isThrowing: false,
            isAsync: false,
            inoutArguments: [0]
        )
        #expect(stub.contains("var inout0 = value; _ = JSONRPCFraming.extractMessages(from: &inout0)"))
    }

    @Test("only the inout position of several is copied")
    func oneOfSeveral() {
        let stub = LiftedTestEmitter.total(
            callee: CalleeReference(bareName: "consume", qualifier: "Reader", argumentLabels: [nil, "limit"]),
            seed: Self.seed,
            generators: ["Gen<Data>.data()", "Gen<Int>.int()"],
            isThrowing: false,
            isAsync: false,
            inoutArguments: [0]
        )
        #expect(stub.contains("var inout0 = args.0; _ = Reader.consume(&inout0, limit: args.1)"))
        #expect(!stub.contains("inout1"))
    }

    /// The control: no inout positions renders exactly as before.
    @Test("no inout arguments changes nothing")
    func noInoutUnchanged() {
        let callee = CalleeReference(bareName: "parse", qualifier: "WikilinkParser")
        let before = LiftedTestEmitter.total(
            callee: callee, seed: Self.seed, generator: "Gen<String>.always(\"x\")",
            isThrowing: false, isAsync: false
        )
        let after = LiftedTestEmitter.total(
            callee: callee, seed: Self.seed, generators: ["Gen<String>.always(\"x\")"],
            isThrowing: false, isAsync: false, inoutArguments: []
        )
        #expect(before == after)
        #expect(!after.contains("inout"))
    }
}
