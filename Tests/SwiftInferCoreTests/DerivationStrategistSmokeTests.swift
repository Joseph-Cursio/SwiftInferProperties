import Testing
import ProtoLawCore

@Suite("ProtoLawCore dep wiring — M3.1 smoke test")
struct DerivationStrategistSmokeTests {

    // PRD §11 / M3.1: prove the `../SwiftProtocolLaws` package dep resolves
    // and `DerivationStrategist.strategy(for:)` is reachable from
    // SwiftInferCore's test target. Strategy A (user-provided `gen()`) is
    // the cheapest path through the strategist — it short-circuits before
    // any `RawType` resolution — so a `hasUserGen: true` shape is the
    // minimal call that exercises the public surface end to end.
    @Test("DerivationStrategist returns .userGen when hasUserGen is true")
    func strategyReturnsUserGenForUserProvidedGenerator() {
        let shape = TypeShape(
            name: "Widget",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: true
        )
        let strategy = DerivationStrategist.strategy(for: shape)
        #expect(strategy == .userGen)
    }
}
