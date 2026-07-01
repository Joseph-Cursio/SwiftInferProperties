import Foundation
import Testing

@testable import SwiftInferCLI

// V1.150 — edge-biased top-level String carrier generator. V1.152 — the
// expression is now sourced from PropertyLawCore's canonical
// `RawType.edgeBiasedGeneratorExpression`; this suite covers the verify-side
// policy (top-level String → edge-biased; other carriers → plain). Escaping is
// covered by the kit's own EdgeBiasedStringGeneratorTests.
@Suite("StrategistDispatchEmitter — V1.150 String edge bias")
struct StringEdgeBiasTests {

    @Test("String carrier mixes the alphanumeric baseline with structural edges")
    func stringCarrierIsEdgeBiased() throws {
        let expr = try #require(StrategistDispatchEmitter.edgeBiasedStringExpression(for: "String"))
        // Keeps the plain alphanumeric arm as the majority (weight 3 vs 2)…
        #expect(expr.contains("Gen<Character>.letterOrNumber.string(of: 0...8)"))
        #expect(expr.contains("Gen.frequency("))
        // …and injects the structural markers that falsify string logic.
        #expect(expr.contains("\"-\""))
        #expect(expr.contains("\"- \""))
        #expect(expr.contains("\"\\n\""))
    }

    @Test("non-String carriers are left to the plain RawType generator")
    func nonStringCarriersUnchanged() {
        #expect(StrategistDispatchEmitter.edgeBiasedStringExpression(for: "Int") == nil)
        #expect(StrategistDispatchEmitter.edgeBiasedStringExpression(for: "Double") == nil)
        #expect(StrategistDispatchEmitter.edgeBiasedStringExpression(for: "Bool") == nil)
    }
}
