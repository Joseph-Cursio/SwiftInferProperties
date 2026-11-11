import SwiftInferCore
import Testing

@testable import SwiftInferCLI

// MARK: - V1.52.D.2 — Pair-resolver integration

@Suite("V1.52.A — Pair-resolver call-site integration")
struct V152PairResolverIntegrationTests {

    private static func entry(
        template: String,
        carrier: String,
        primary: String,
        hash: String = "0xCAFEBABEDEADBEEF"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: hash,
            templateName: template,
            score: 60,
            tier: "Strong",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-13T00:00:00Z",
            lastSeenAt: "2026-05-13T00:00:00Z",
            typeName: carrier
        )
    }

    @Test("round-trip on Complex with exp(_:) emits Complex.exp / Complex.log (V1.54.A)")
    func roundTripExpEmitsStaticMethod() throws {
        let result = try RoundTripPairResolver.resolve(
            Self.entry(template: "round-trip", carrier: "Complex<Double>", primary: "exp(_:)")
        )
        #expect(result.forwardCall == "Complex.exp")
        #expect(result.inverseCall == "Complex.log")
    }

    @Test("commutativity on Complex with operator name `+` emits paren form")
    func commutativityOperatorEmitsParenForm() throws {
        let result = try CommutativityPairResolver.resolve(
            Self.entry(template: "commutativity", carrier: "Complex<Double>", primary: "+(z:w:)")
        )
        #expect(result.functionCall == "(+)")
    }

    @Test("associativity on Complex with operator name `*` emits paren form")
    func associativityOperatorEmitsParenForm() throws {
        let result = try AssociativityPairResolver.resolve(
            Self.entry(template: "associativity", carrier: "Complex<Double>", primary: "*(z:w:)")
        )
        #expect(result.functionCall == "(*)")
    }

    @Test("monotonicity on Double with log(onePlus:) emits Double.log (V1.54.A)")
    func monotonicityLogOnePlusEmitsStaticMethod() throws {
        let result = try MonotonicityPairResolver.resolve(
            Self.entry(template: "monotonicity", carrier: "Double", primary: "log(onePlus:)")
        )
        #expect(result.functionCall == "Double.log")
    }
}
