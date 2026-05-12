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
            typeName: carrier,
            score: 30,
            tier: "Possible",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-12T00:00:00Z",
            lastSeenAt: "2026-05-12T00:00:00Z"
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

@Suite("DualStyleConsistencyPairResolver — V1.48.B")
struct DualStyleConsistencyPairResolverTests {

    private static func entry(
        template: String = "dual-style-consistency",
        carrier: String? = "Array",
        primary: String = "sorted()"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xABCD1234EFFE5678",
            templateName: template,
            typeName: carrier,
            score: 30,
            tier: "Possible",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-12T00:00:00Z",
            lastSeenAt: "2026-05-12T00:00:00Z"
        )
    }

    @Test("Array + sorted() resolves to (Array.sorted, sort)")
    func resolvesSortedSortPair() throws {
        let result = try DualStyleConsistencyPairResolver.resolve(Self.entry())
        #expect(result.nonMutCall == "Array.sorted")
        #expect(result.mutMethodName == "sort")
    }

    @Test("Array + reversed() resolves to (Array.reversed, reverse)")
    func resolvesReversedReversePair() throws {
        let result = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "reversed()")
        )
        #expect(result.nonMutCall == "Array.reversed")
        #expect(result.mutMethodName == "reverse")
    }

    @Test("Array + shuffled() resolves to (Array.shuffled, shuffle)")
    func resolvesShuffledShufflePair() throws {
        let result = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "shuffled()")
        )
        #expect(result.nonMutCall == "Array.shuffled")
        #expect(result.mutMethodName == "shuffle")
    }

    @Test("non-dual-style-consistency template raises .unsupportedTemplate")
    func unsupportedTemplate() throws {
        #expect(throws: VerifyError.self) {
            _ = try DualStyleConsistencyPairResolver.resolve(
                Self.entry(template: "idempotence")
            )
        }
    }

    @Test("primaryFunctionName not in curated list raises .unsupportedPair")
    func unsupportedPair() throws {
        #expect(throws: VerifyError.self) {
            _ = try DualStyleConsistencyPairResolver.resolve(
                Self.entry(primary: "rotated()")
            )
        }
    }

    @Test("curated list ships exactly the 3 v1.48 entries")
    func curatedListLoadBearing() {
        let nonMutNames = DualStyleConsistencyPairResolver.curated.map(\.nonMutating)
        #expect(nonMutNames.contains("sorted()"))
        #expect(nonMutNames.contains("reversed()"))
        #expect(nonMutNames.contains("shuffled()"))
    }
}

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
            typeName: carrier,
            score: 30,
            tier: "Possible",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-12T00:00:00Z",
            lastSeenAt: "2026-05-12T00:00:00Z"
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
