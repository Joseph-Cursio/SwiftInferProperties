import Foundation
import Testing

@testable import SwiftInferCLI

/// The strategist-routed codable-round-trip composer — the live-index emit path
/// (`composeCodableRoundTripPass`). Asserts the emitted stub's JSON oracle + the
/// standard VERIFY_* markers, using an `Int` carrier (Codable & Equatable, raw
/// generator — no typeShape needed).
@Suite("StrategistDispatchEmitter — codable-round-trip composer")
struct StrategistDispatchEmitterCodableTests {

    private static let seed = StrategistDispatchEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    private func emit(carrier: String) throws -> String {
        try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: carrier,
                typeShape: nil,
                template: "codable-round-trip",
                functionCalls: [],
                extraImports: [],
                seedHex: Self.seed,
                trialBudget: .small
            )
        )
    }

    @Test("emits the JSON encode/decode round-trip oracle over the carrier")
    func jsonOracleShape() throws {
        let source = try emit(carrier: "Int")
        #expect(source.contains("import Foundation"))
        #expect(source.contains("JSONEncoder()"))
        #expect(source.contains("JSONDecoder()"))
        #expect(source.contains("roundTripEncoder.encode(value)"))
        #expect(source.contains("roundTripDecoder.decode(Int.self, from: encoded)"))
        #expect(source.contains("if decoded != value"))
        #expect(source.contains("defaultGenerator.run(using: &rng)"))
    }

    @Test("emits the standard VERIFY_* marker contract, including the codec-throw FAIL arm")
    func markerContract() throws {
        let source = try emit(carrier: "Int")
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(source.contains("VERIFY_DEFAULT_DECODED"))
        #expect(source.contains("codec threw"))
        #expect(source.contains("exit(1)"))
    }
}
