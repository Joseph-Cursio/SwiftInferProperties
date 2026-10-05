import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The actor-instance and operator determinism stubs, frozen as whole literals.
///
/// `DeterminismCalleeEmitterTests` pins the other call shapes with `contains`, and its no-drift
/// row compares `deterministic(callee:)` with `agreementProperty`, which `deterministic` now calls
/// — so it cannot see the shared emitter's text move for every caller at once. These literals can.
/// They were taken from this branch and checked byte for byte against f87bb241's emitter (this
/// file run against that commit's sources), before the reference oracle shared it.
@Suite("Determinism — the actor-instance and operator stubs, frozen")
struct DeterminismFrozenStubTests {

    private static let seed = SamplingSeed.Value(stateA: 0x1, stateB: 0x2, stateC: 0x3, stateD: 0x4)

    /// A receiver or operand drawn from its type's generator, and a `String` argument.
    private static let ledgerAndString = ["Ledger.gen()", "Gen<String>.always(\"x\")"]

    private static func emit(
        _ callee: CalleeReference,
        generators: [String],
        argumentTypes: [String],
        isThrows: Bool = false
    ) -> String {
        LiftedTestEmitter.deterministic(
            callee: callee,
            generators: generators,
            seed: seed,
            isThrows: isThrows,
            argumentTypes: argumentTypes
        )
    }

    /// One `await` reaches the actor, on the receiver drawn first.
    @Test func anActorInstanceMethod() {
        let stub = Self.emit(
            CalleeReference(bareName: "count", argumentLabels: ["of"], isolation: "actor", isInstanceMethod: true),
            generators: Self.ledgerAndString,
            argumentTypes: ["Ledger", "String"]
        )
        #expect(stub == Self.actorInstance)
    }

    @Test func aThrowingActorInstanceMethod() {
        let stub = Self.emit(
            CalleeReference(bareName: "balance", argumentLabels: ["for"], isolation: "actor", isInstanceMethod: true),
            generators: Self.ledgerAndString,
            argumentTypes: ["Ledger", "String"],
            isThrows: true
        )
        #expect(stub == Self.throwingActorInstance)
    }

    /// An operator is applied infix, and its label names the qualified operator.
    @Test func anOperator() {
        let stub = Self.emit(
            CalleeReference(bareName: "+", qualifier: "Money", argumentLabels: [nil, nil]),
            generators: ["Money.gen()", "Money.gen()"],
            argumentTypes: ["Money", "Money"]
        )
        #expect(stub == Self.staticOperator)
    }

    // swiftlint:disable line_length
    static let actorInstance = "\n" + #"""
        @Test func count_isDeterministic() async {
            let backend = SwiftPropertyBasedBackend()
            let seed = Seed(
                stateA: 0x0000000000000001,
                stateB: 0x0000000000000002,
                stateC: 0x0000000000000003,
                stateD: 0x0000000000000004
            )
            let result = await backend.check(
                trials: 100,
                seed: seed,
                sample: { rng in
                            let arg0 = (Ledger.gen()).run(using: &rng)
                            let arg1 = (Gen<String>.always("x")).run(using: &rng)
                            return (arg0, arg1)
                        },
                property: { (args: (Ledger, String)) in await args.0.count(of: args.1) == args.0.count(of: args.1) }
            )
            if case let .failed(_, _, input, error) = result {
                Issue.record(
                    "count(of:) is not deterministic — same input produced different output at input \(input). \(error?.message ?? "")"
                )
            }
        }
        """#

    static let throwingActorInstance = "\n" + #"""
        @Test func balance_isDeterministic() async {
            let backend = SwiftPropertyBasedBackend()
            let seed = Seed(
                stateA: 0x0000000000000001,
                stateB: 0x0000000000000002,
                stateC: 0x0000000000000003,
                stateD: 0x0000000000000004
            )
            let result = await backend.check(
                trials: 100,
                seed: seed,
                sample: { rng in
                            let arg0 = (Ledger.gen()).run(using: &rng)
                            let arg1 = (Gen<String>.always("x")).run(using: &rng)
                            return (arg0, arg1)
                        },
                property: { (args: (Ledger, String)) in await (try? args.0.balance(for: args.1)) == (try? args.0.balance(for: args.1)) }
            )
            if case let .failed(_, _, input, error) = result {
                Issue.record(
                    "balance(for:) is not deterministic — same input produced different output at input \(input). \(error?.message ?? "")"
                )
            }
        }
        """#

    static let staticOperator = "\n" + #"""
        @Test func plus_isDeterministic() async {
            let backend = SwiftPropertyBasedBackend()
            let seed = Seed(
                stateA: 0x0000000000000001,
                stateB: 0x0000000000000002,
                stateC: 0x0000000000000003,
                stateD: 0x0000000000000004
            )
            let result = await backend.check(
                trials: 100,
                seed: seed,
                sample: { rng in
                            let arg0 = (Money.gen()).run(using: &rng)
                            let arg1 = (Money.gen()).run(using: &rng)
                            return (arg0, arg1)
                        },
                property: { (args: (Money, Money)) in (args.0 + args.1) == (args.0 + args.1) }
            )
            if case let .failed(_, _, input, error) = result {
                Issue.record(
                    "Money.+(_:_:) is not deterministic — same input produced different output at input \(input). \(error?.message ?? "")"
                )
            }
        }
        """#
    // swiftlint:enable line_length
}
