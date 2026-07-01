import Foundation
import Testing

@testable import SwiftInferCLI

// V1.150 — edge-biased top-level String carrier generator.
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

    @Test("swiftStringLiteral escapes quotes, backslashes, newlines, and tabs")
    func literalEscaping() {
        #expect(StrategistDispatchEmitter.swiftStringLiteral("-") == "\"-\"")
        #expect(StrategistDispatchEmitter.swiftStringLiteral("") == "\"\"")
        #expect(StrategistDispatchEmitter.swiftStringLiteral("\n") == "\"\\n\"")
        #expect(StrategistDispatchEmitter.swiftStringLiteral("\t") == "\"\\t\"")
        #expect(StrategistDispatchEmitter.swiftStringLiteral("a\"b\\c") == "\"a\\\"b\\\\c\"")
    }
}
