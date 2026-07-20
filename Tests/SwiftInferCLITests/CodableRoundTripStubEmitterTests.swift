@testable import SwiftInferCLI
import Testing

/// The codable-round-trip stub emitter — the generic JSON round-trip verifier
/// (`decode(encode(x)) == x`) generated for a custom-`Codable` carrier.
@Suite("CodableRoundTripStubEmitter — JSON round-trip verifier")
struct CodableRoundTripStubEmitterTests {

    private func emitted(_ carrier: String, _ value: String) -> String {
        CodableRoundTripStubEmitter.emit(
            .init(carrierType: carrier, valueExpression: value, trials: 500)
        )
    }

    @Test("emits the JSON encode/decode round-trip harness over the carrier")
    func harnessShape() {
        let source = emitted("Ratio", "Ratio(value: Double(rng.next() % 100))")
        #expect(source.contains("import Foundation"))
        #expect(source.contains("JSONEncoder()"))
        #expect(source.contains("decoder.decode(Ratio.self, from: data)"))
        #expect(source.contains("let value: Ratio = Ratio(value: Double(rng.next() % 100))"))
        #expect(source.contains("if back != value"))
    }

    @Test("emits the standard VERIFY_* marker contract with the trial budget")
    func markerContract() {
        let source = emitted("Ratio", "Ratio(value: 1.0)")
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_TRIALS: 500"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("exit(1)"))
    }

    @Test("threads extra module imports for a path-dependency corpus")
    func extraImports() {
        let source = CodableRoundTripStubEmitter.emit(
            .init(carrierType: "Ratio", valueExpression: "Ratio(value: 1.0)", extraImports: ["CorpusModule"])
        )
        #expect(source.contains("import Foundation"))
        #expect(source.contains("import CorpusModule"))
    }
}
