import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

// V1.48.F — unit tests for the three new pair resolvers
// (IdempotenceLiftedPairResolver, DualStyleConsistencyPairResolver,
// MonotonicityPairResolver).

@Suite("IdempotenceLiftedPairResolver — V1.48.B")
struct IdempotenceLiftedPairResolverTests {

    private static func entry(
        template: String = "idempotence-lifted",
        carrier: String? = "Int",
        primary: String = "sort()"
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

    @Test("Int + sort() resolves to Int.sort")
    func resolvesIntSort() throws {
        let result = try IdempotenceLiftedPairResolver.resolve(Self.entry())
        #expect(result.functionCall == "Int.sort")
    }

    @Test("non-idempotence-lifted template raises .unsupportedTemplate")
    func unsupportedTemplate() throws {
        #expect(throws: VerifyError.self) {
            _ = try IdempotenceLiftedPairResolver.resolve(
                Self.entry(template: "idempotence")
            )
        }
    }

    @Test("String carrier passes (resolver is carrier-agnostic)")
    func stringCarrierPasses() throws {
        let result = try IdempotenceLiftedPairResolver.resolve(
            Self.entry(carrier: "String", primary: "normalized()")
        )
        #expect(result.functionCall == "String.normalized")
    }

    @Test("nil carrier produces '(none)' qualifier")
    func nilCarrier() throws {
        let result = try IdempotenceLiftedPairResolver.resolve(
            Self.entry(carrier: nil)
        )
        #expect(result.functionCall == "(none).sort")
    }
}
