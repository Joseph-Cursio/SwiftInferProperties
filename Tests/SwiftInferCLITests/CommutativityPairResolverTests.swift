import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// V1.45.B — CommutativityPairResolver tests. Mirrors
/// IdempotencePairResolverTests for the single-function
/// two-argument shape.
@Suite("CommutativityPairResolver — V1.45.B resolve")
struct CommutativityPairResolverTests {

    private static func entry(
        template: String = "commutativity",
        carrier: String? = "Int",
        primary: String = "binomial(n:k:)",
        hash: String = "0xBC43359C0574816B"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: hash,
            templateName: template,
            typeName: carrier,
            score: 30,
            tier: "Possible",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-11T00:00:00Z",
            lastSeenAt: "2026-05-11T00:00:00Z"
        )
    }

    @Test("Int + binomial(n:k:) → Int.binomial")
    func resolvesIntBinomial() throws {
        let result = try CommutativityPairResolver.resolve(Self.entry())
        #expect(result.functionCall == "Int.binomial")
    }

    @Test("Complex<Double> + add(_:_:) → Complex.add")
    func resolvesComplexAdd() throws {
        let result = try CommutativityPairResolver.resolve(
            Self.entry(carrier: "Complex<Double>", primary: "add(_:_:)")
        )
        #expect(result.functionCall == "Complex.add")
    }

    @Test("Double + max(_:_:) → Double.max")
    func resolvesDoubleMax() throws {
        let result = try CommutativityPairResolver.resolve(
            Self.entry(carrier: "Double", primary: "max(_:_:)")
        )
        #expect(result.functionCall == "Double.max")
    }

    @Test("non-commutativity template raises .unsupportedTemplate")
    func unsupportedTemplate() throws {
        do {
            _ = try CommutativityPairResolver.resolve(Self.entry(template: "round-trip"))
            Issue.record("expected .unsupportedTemplate")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedTemplate(template, expected):
                #expect(template == "round-trip")
                #expect(expected == ["commutativity"])
            default:
                Issue.record("expected .unsupportedTemplate; got \(error)")
            }
        }
    }

    @Test("unsupported carrier raises .unsupportedCarrier")
    func unsupportedCarrier() throws {
        do {
            _ = try CommutativityPairResolver.resolve(Self.entry(carrier: "Array<Int>"))
            Issue.record("expected .unsupportedCarrier")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedCarrier(carrier, expected):
                #expect(carrier == "Array<Int>")
                #expect(expected == CommutativityStubEmitter.supportedCarriers)
            default:
                Issue.record("expected .unsupportedCarrier; got \(error)")
            }
        }
    }

    @Test("nil carrier raises .unsupportedCarrier with '(none)' sentinel")
    func nilCarrier() throws {
        do {
            _ = try CommutativityPairResolver.resolve(Self.entry(carrier: nil))
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
