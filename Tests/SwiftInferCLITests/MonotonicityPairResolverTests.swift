import SwiftInferCore
import Testing

@testable import SwiftInferCLI

@Suite("MonotonicityPairResolver — V1.48.B")
struct MonotonicityPairResolverTests {

    private static func entry(
        template: String = "monotonicity",
        carrier: String? = "Int",
        primary: String = "doubled()"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xABCD1234EFFE5678",
            templateName: template,
            score: 30,
            tier: "Possible",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-12T00:00:00Z",
            lastSeenAt: "2026-05-12T00:00:00Z",
            typeName: carrier
        )
    }

    @Test("Int + doubled() resolves to Int.doubled")
    func resolvesIntDoubled() throws {
        let result = try MonotonicityPairResolver.resolve(Self.entry())
        #expect(result.functionCall == "Int.doubled")
    }

    @Test("String carrier passes (Comparable surface)")
    func stringCarrierPasses() throws {
        let result = try MonotonicityPairResolver.resolve(
            Self.entry(carrier: "String", primary: "lowercased()")
        )
        #expect(result.functionCall == "String.lowercased")
    }

    @Test("non-monotonicity template raises .unsupportedTemplate")
    func unsupportedTemplate() throws {
        #expect(throws: VerifyError.self) {
            _ = try MonotonicityPairResolver.resolve(
                Self.entry(template: "idempotence")
            )
        }
    }
}
