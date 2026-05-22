import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// V1.44.D — IdempotencePairResolver tests. Single-function analog of
/// RoundTripPairResolverTests; no curated pair list, no inverse.
@Suite("IdempotencePairResolver — V1.44.D resolve")
struct IdempotencePairResolverTests {

    private static func entry(
        template: String = "idempotence",
        carrier: String? = "Complex<Double>",
        primary: String = "normalize(_:)",
        hash: String = "0xBC43359C0574816B"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: hash,
            templateName: template,
            typeName: carrier,
            score: 50,
            tier: "Possible",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-11T00:00:00Z",
            lastSeenAt: "2026-05-11T00:00:00Z"
        )
    }

    // MARK: - Happy paths

    @Test("Complex<Double> + normalize(_:) → Complex.normalize")
    func resolvesComplexDoubleNormalize() throws {
        let result = try IdempotencePairResolver.resolve(Self.entry())
        #expect(result.functionCall == "Complex.normalize")
    }

    @Test("Double + abs(_:) → Double.abs")
    func resolvesDoubleAbs() throws {
        let result = try IdempotencePairResolver.resolve(
            Self.entry(carrier: "Double", primary: "abs(_:)")
        )
        #expect(result.functionCall == "Double.abs")
    }

    @Test("Int + signum(_:) → Int.signum")
    func resolvesIntSignum() throws {
        let result = try IdempotencePairResolver.resolve(
            Self.entry(carrier: "Int", primary: "signum(_:)")
        )
        #expect(result.functionCall == "Int.signum")
    }

    @Test("primary name without parameter-label suffix passes through unchanged")
    func resolvesBareName() throws {
        let result = try IdempotencePairResolver.resolve(
            Self.entry(primary: "normalize")
        )
        #expect(result.functionCall == "Complex.normalize")
    }

    // MARK: - Error paths

    @Test("non-idempotence template raises .unsupportedTemplate")
    func unsupportedTemplate() throws {
        do {
            _ = try IdempotencePairResolver.resolve(Self.entry(template: "round-trip"))
            Issue.record("expected .unsupportedTemplate")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedTemplate(template, expected):
                #expect(template == "round-trip")
                #expect(expected == ["idempotence"])

            default:
                Issue.record("expected .unsupportedTemplate; got \(error)")
            }
        }
    }

    @Test("unsupported carrier raises .unsupportedCarrier")
    func unsupportedCarrier() throws {
        do {
            _ = try IdempotencePairResolver.resolve(Self.entry(carrier: "Array<Int>"))
            Issue.record("expected .unsupportedCarrier")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedCarrier(carrier, expected):
                #expect(carrier == "Array<Int>")
                #expect(expected == IdempotenceStubEmitter.supportedCarriers)

            default:
                Issue.record("expected .unsupportedCarrier; got \(error)")
            }
        }
    }

    @Test("nil carrier raises .unsupportedCarrier with '(none)' sentinel")
    func nilCarrier() throws {
        do {
            _ = try IdempotencePairResolver.resolve(Self.entry(carrier: nil))
            Issue.record("expected .unsupportedCarrier")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedCarrier(carrier, _):
                #expect(carrier == "(none)")

            default:
                Issue.record("expected .unsupportedCarrier; got \(error)")
            }
        }
    }
}
