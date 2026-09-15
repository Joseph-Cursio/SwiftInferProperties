import SwiftInferCore
import SwiftInferTemplates
import Testing

/// Totality at every application arity (#464).
///
/// Every other arm's arity is part of its law — `f(f(x))` needs exactly one argument — so
/// holding totality to the same rule looked consistent and was not: totality calls once and
/// discards the result, and "returns or throws for every input" is as well-formed for
/// `graph.matchesSearch(node)` as for `parse(_:)`. The corpus funnel census measured the cost of
/// the arity-1 rule at **497 entailed laws declined**, the largest single loss it found.
@Suite("Totality — any arity, the receiver drawn first")
struct TotalityAnyArityEmitterTests {

    private static let seed = SamplingSeed.Value(
        stateA: 0x1234_5678_9ABC_DEF0,
        stateB: 0x0FED_CBA9_8765_4321,
        stateC: 0xAAAA_BBBB_CCCC_DDDD,
        stateD: 0x1111_2222_3333_4444
    )

    private static func emit(
        _ callee: CalleeReference,
        generators: [String],
        isThrowing: Bool = false,
        isAsync: Bool = false
    ) -> String {
        LiftedTestEmitter.total(
            callee: callee,
            seed: seed,
            generators: generators,
            isThrowing: isThrowing,
            isAsync: isAsync
        )
    }

    /// **The load-bearing negative.** A single generator must render byte-for-byte as the
    /// single-generator overload always did — otherwise every totality stub already emitted
    /// changes shape alongside a fix that was about the ones that were never emitted.
    @Test func oneGeneratorIsTheUnaryStubExactly() {
        let callee = CalleeReference(bareName: "parse", qualifier: "WikilinkParser")
        let unary = LiftedTestEmitter.total(
            callee: callee,
            seed: Self.seed,
            generator: "Gen<String>.always(\"x\")",
            isThrowing: false,
            isAsync: false
        )
        #expect(Self.emit(callee, generators: ["Gen<String>.always(\"x\")"]) == unary)
    }

    /// The measured witness, reduced: an instance method with one parameter needs two arguments,
    /// and the receiver is the first.
    @Test func anInstanceMethodDrawsItsReceiverFirst() {
        let stub = Self.emit(
            CalleeReference(bareName: "matchesSearch", argumentLabels: [nil], isInstanceMethod: true),
            generators: ["Graph.gen()", "Gen<String>.always(\"x\")"]
        )
        #expect(stub.contains("let arg0 = (Graph.gen()).run(using: &rng)"))
        #expect(stub.contains("let arg1 = (Gen<String>.always(\"x\")).run(using: &rng)"))
        #expect(stub.contains("return (arg0, arg1)"))
        #expect(stub.contains("{ args in _ = args.0.matchesSearch(args.1); return true }"))
    }

    /// A static function of two parameters keeps its qualifier and its labels, positionally.
    @Test func aMultiParameterStaticFunctionIsCalledWithEveryLabel() {
        let stub = Self.emit(
            CalleeReference(bareName: "isNeighbor", qualifier: "GraphCanvas", argumentLabels: [nil, "of"]),
            generators: ["Gen<Int>.int()", "Gen<Int>.int()"]
        )
        #expect(stub.contains("_ = GraphCanvas.isNeighbor(args.0, of: args.1); return true"))
    }

    /// A nullary instance method is arity 1 — the receiver alone — and so draws one value, not a
    /// one-element tuple.
    @Test func aReceiverOnlySubjectDrawsOneValue() {
        let stub = Self.emit(
            CalleeReference(bareName: "isBlank", isInstanceMethod: true),
            generators: ["Line.gen()"]
        )
        #expect(stub.contains("{ rng in (Line.gen()).run(using: &rng) }"))
        #expect(stub.contains("{ value in _ = value.isBlank(); return true }"))
        #expect(stub.contains("args") == false)
    }

    /// The hop still wraps the whole body, now over the tuple binding.
    @Test func anIsolatedMultiArgumentSubjectHopsOnce() {
        let stub = Self.emit(
            CalleeReference(
                bareName: "includes",
                argumentLabels: [nil],
                isolation: "MainActor",
                isInstanceMethod: true
            ),
            generators: ["Store.gen()", "Gen<String>.always(\"x\")"]
        )
        #expect(stub.contains("{ args in await MainActor.run { _ = args.0.includes(args.1); return true } }"))
    }

    @Test func aThrowingMultiArgumentSubjectIsAllowedToThrow() {
        let stub = Self.emit(
            CalleeReference(bareName: "decode", qualifier: "Codec", argumentLabels: ["from", "as"]),
            generators: ["Gen<String>.always(\"x\")", "Gen<Int>.int()"],
            isThrowing: true
        )
        #expect(stub.contains("_ = try? Codec.decode(from: args.0, as: args.1); return true"))
    }
}
