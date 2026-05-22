import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// V1.46.B — AssociativityPairResolver tests. Mirrors
/// CommutativityPairResolverTests for the single-function
/// three-argument shape.
@Suite("AssociativityPairResolver — V1.46.B resolve")
struct AssociativityPairResolverTests {

    private static func entry(
        template: String = "associativity",
        carrier: String? = "Int",
        primary: String = "distance(from:to:)",
        hash: String = "0x518A359C0574816B"
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

    @Test("Int + distance(from:to:) → Int.distance")
    func resolvesIntDistance() throws {
        let result = try AssociativityPairResolver.resolve(Self.entry())
        #expect(result.functionCall == "Int.distance")
    }

    @Test("Complex<Double> + _relaxedMul(_:_:) → Complex._relaxedMul")
    func resolvesComplexRelaxedMul() throws {
        let result = try AssociativityPairResolver.resolve(
            Self.entry(carrier: "Complex<Double>", primary: "_relaxedMul(_:_:)")
        )
        #expect(result.functionCall == "Complex._relaxedMul")
    }

    @Test("Double + max(_:_:) → Double.max")
    func resolvesDoubleMax() throws {
        let result = try AssociativityPairResolver.resolve(
            Self.entry(carrier: "Double", primary: "max(_:_:)")
        )
        #expect(result.functionCall == "Double.max")
    }

    @Test("non-associativity template raises .unsupportedTemplate")
    func unsupportedTemplate() throws {
        do {
            _ = try AssociativityPairResolver.resolve(Self.entry(template: "commutativity"))
            Issue.record("expected .unsupportedTemplate")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedTemplate(template, expected):
                #expect(template == "commutativity")
                #expect(expected == ["associativity"])

            default:
                Issue.record("expected .unsupportedTemplate; got \(error)")
            }
        }
    }

    @Test("unsupported carrier raises .unsupportedCarrier")
    func unsupportedCarrier() throws {
        do {
            _ = try AssociativityPairResolver.resolve(Self.entry(carrier: "Array<Int>"))
            Issue.record("expected .unsupportedCarrier")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedCarrier(carrier, expected):
                #expect(carrier == "Array<Int>")
                #expect(expected == AssociativityStubEmitter.supportedCarriers)

            default:
                Issue.record("expected .unsupportedCarrier; got \(error)")
            }
        }
    }

    @Test("nil carrier raises .unsupportedCarrier with '(none)' sentinel")
    func nilCarrier() throws {
        do {
            _ = try AssociativityPairResolver.resolve(Self.entry(carrier: nil))
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
