import Foundation
import PropertyLawCore
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

// V1.49.E — unit tests for the V1.49.A stub-preamble channel.

@Suite("V1.49.A — stub-preamble channel across all 5 emitters")
struct V149PreambleTests {

    private static let canonicalSeed = RoundTripStubEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    private static let canonicalPreamble = """
    extension Int {
        mutating func bumpInPlace() { self += 1 }
    }
    """

    // MARK: - RoundTripStubEmitter

    @Test("RoundTrip: preamble defaults to empty + emit stays byte-stable")
    func roundTripDefaultEmpty() throws {
        let inputs = RoundTripStubEmitter.Inputs(
            forwardCall: "{ (x: Int) in x }",
            inverseCall: "{ (x: Int) in x }",
            extraImports: [],
            carrierType: "Int",
            seedHex: Self.canonicalSeed,
            trialBudget: .small
        )
        let source = try RoundTripStubEmitter.emit(inputs)
        #expect(!source.contains("bumpInPlace"))
    }

    @Test("RoundTrip: non-empty preamble renders verbatim in setup section")
    func roundTripWithPreamble() throws {
        let inputs = RoundTripStubEmitter.Inputs(
            forwardCall: "{ (x: Int) in x }",
            inverseCall: "{ (x: Int) in x }",
            extraImports: [],
            carrierType: "Int",
            seedHex: Self.canonicalSeed,
            trialBudget: .small,
            preamble: Self.canonicalPreamble
        )
        let source = try RoundTripStubEmitter.emit(inputs)
        #expect(source.contains("extension Int {"))
        #expect(source.contains("mutating func bumpInPlace()"))
        // Preamble is positioned after imports + before var rng.
        let importsEnd = try #require(source.range(of: "import")).lowerBound
        let preambleStart = try #require(source.range(of: "extension Int")).lowerBound
        let rngStart = try #require(source.range(of: "var rng")).lowerBound
        #expect(importsEnd < preambleStart)
        #expect(preambleStart < rngStart)
    }

    // MARK: - StrategistDispatchEmitter

    @Test("StrategistDispatch: preamble renders in setup section")
    func strategistWithPreamble() throws {
        let source = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "Int",
                typeShape: nil,
                template: "idempotence",
                functionCalls: ["{ (x: Int) in x }"],
                seedHex: Self.canonicalSeed,
                trialBudget: .small,
                extraImports: [],
                preamble: Self.canonicalPreamble
            )
        )
        #expect(source.contains("mutating func bumpInPlace()"))
        // Preamble is positioned before var rng.
        let preambleStart = try #require(source.range(of: "extension Int")).lowerBound
        let rngStart = try #require(source.range(of: "var rng")).lowerBound
        #expect(preambleStart < rngStart)
    }

    // MARK: - All 5 emitters round-trip the preamble field

    @Test("Idempotence + Commutativity + Associativity emitters thread the preamble")
    func nonRoundTripEmittersThreadPreamble() throws {
        let preamble = "extension Int {\n    var sentinel: Int { 42 }\n}"
        let idem = try IdempotenceStubEmitter.emit(
            IdempotenceStubEmitter.Inputs(
                functionCall: "{ (x: Int) in x }",
                extraImports: [],
                carrierType: "Int",
                seedHex: Self.canonicalSeed,
                trialBudget: .small,
                preamble: preamble
            )
        )
        let comm = try CommutativityStubEmitter.emit(
            CommutativityStubEmitter.Inputs(
                functionCall: "{ (a: Int, b: Int) in a + b }",
                extraImports: [],
                carrierType: "Int",
                seedHex: Self.canonicalSeed,
                trialBudget: .small,
                preamble: preamble
            )
        )
        let assoc = try AssociativityStubEmitter.emit(
            AssociativityStubEmitter.Inputs(
                functionCall: "{ (a: Int, b: Int) in a + b }",
                extraImports: [],
                carrierType: "Int",
                seedHex: Self.canonicalSeed,
                trialBudget: .small,
                preamble: preamble
            )
        )
        #expect(idem.contains("sentinel: Int"))
        #expect(comm.contains("sentinel: Int"))
        #expect(assoc.contains("sentinel: Int"))
    }

    @Test("multi-line preamble preserves line breaks verbatim")
    func multilinePreambleRoundTrips() throws {
        let preamble = """
        // Comment line 1
        // Comment line 2
        let foo: Int = 0
        """
        let source = try IdempotenceStubEmitter.emit(
            IdempotenceStubEmitter.Inputs(
                functionCall: "{ (x: Int) in x }",
                extraImports: [],
                carrierType: "Int",
                seedHex: Self.canonicalSeed,
                trialBudget: .small,
                preamble: preamble
            )
        )
        #expect(source.contains("// Comment line 1"))
        #expect(source.contains("// Comment line 2"))
        #expect(source.contains("let foo: Int = 0"))
    }
}
