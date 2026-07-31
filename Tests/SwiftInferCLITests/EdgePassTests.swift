import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import Testing

/// Pass 2 for strategist-routed carriers.
///
/// It used to be `edgeSentinelSection()` — a hardcoded
/// `print("VERIFY_EDGE_RESULT: PASS")` with zero trials, asserting nothing,
/// which the renderer then reported as if an edge pass had run.
/// `fixtures/verify-refutability` measured the consequence: `mergedBound(_:)`,
/// wrong *only* at `Int.min`, came back holding. It now returns
/// `measured-edgeCaseAdvisory`.
@Suite("StrategistDispatchEmitter — advisory edge pass")
struct EdgePassTests {

    private static let seed = StrategistDispatchEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    private static func inputs(
        carrier: String,
        template: String = "commutativity",
        calls: [String] = ["combine"]
    ) -> StrategistDispatchEmitter.Inputs {
        StrategistDispatchEmitter.Inputs(
            carrier: carrier,
            typeShape: nil,
            template: template,
            functionCalls: calls,
            seedHex: seed,
            trialBudget: .small
        )
    }

    // MARK: - The curated domains

    @Test("a signed carrier's boundary set spans min, max, zero and both units")
    func signedDomain() throws {
        let values = try #require(StrategistDispatchEmitter.edgeDomainValues(for: "Int"))
        #expect(values == ["Int.min", "Int.max", "0", "-1", "1"])
    }

    /// `-1` does not compile as an unsigned literal, and `min` is `0`.
    @Test("an unsigned carrier's boundary set omits the negatives")
    func unsignedDomain() throws {
        let values = try #require(StrategistDispatchEmitter.edgeDomainValues(for: "UInt"))
        #expect(!values.contains("-1"))
        #expect(!values.contains("UInt.min"))
        #expect(values.contains("UInt.max"))
    }

    @Test("fixed-width carriers get their own extremes")
    func fixedWidthDomain() throws {
        let values = try #require(StrategistDispatchEmitter.edgeDomainValues(for: "Int8"))
        #expect(values.contains("Int8.min"))
        #expect(values.contains("Int8.max"))
    }

    @Test("String's boundary set leads with the empty string")
    func stringDomain() throws {
        let values = try #require(StrategistDispatchEmitter.edgeDomainValues(for: "String"))
        #expect(values.first == #""""#)
    }

    /// A carrier with no meaningful finite boundary set keeps the sentinel, and
    /// the renderer then says no edge pass ran.
    @Test("a carrier with no curated boundary set has no edge domain")
    func noDomainForOtherCarriers() {
        #expect(StrategistDispatchEmitter.edgeDomainValues(for: "Bool") == nil)
        #expect(StrategistDispatchEmitter.edgeDomainValues(for: "Blob") == nil)
    }

    // MARK: - The emitted pass

    /// The law is composed once and reused, so it cannot drift between passes.
    /// What distinguishes Pass 2 is the generator and the marker prefix.
    @Test("an Int carrier emits a real Pass 2 over the boundary values")
    func intCarrierEmitsRealEdgePass() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(carrier: "Int"))
        #expect(source.contains("VERIFY_EDGE_RESULT"))
        #expect(source.contains("Int.min"))
        #expect(source.contains("Int.max"))
        // The zero-trial sentinel must be gone.
        #expect(!source.contains("VERIFY_EDGE_TRIALS: 0"))
    }

    /// Both passes declare bindings with the same names (`defaultGenerator`,
    /// `applyOnce`, …). Pass 2 is wrapped in `do { }` so those shadow rather
    /// than redeclare — which is what lets the composer be reused verbatim.
    @Test("Pass 2 is scoped so its bindings shadow rather than collide")
    func edgePassIsScoped() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(carrier: "Int"))
        #expect(source.contains("do {"))
        #expect(source.components(separatedBy: "let defaultGenerator").count - 1 == 2)
    }

    @Test("a carrier with no boundary set still gets the sentinel")
    func boolCarrierKeepsSentinel() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(carrier: "Bool"))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"))
    }

    // MARK: - The relabel contract

    @Test("the relabel rewrites every default marker")
    func relabelRewritesMarkers() throws {
        let body = """
        print("VERIFY_DEFAULT_RESULT: FAIL")
        print("VERIFY_DEFAULT_TRIAL: 3")
        """
        let edge = try #require(StrategistDispatchEmitter.edgePassBody(fromDefaultBody: body))
        #expect(edge.contains("VERIFY_EDGE_RESULT"))
        #expect(edge.contains("VERIFY_EDGE_TRIAL"))
        #expect(!edge.contains("VERIFY_DEFAULT_"))
    }

    /// **Fails closed.** A composer shape carrying no default marker would
    /// relabel into a pass that prints nothing and asserts nothing — reporting
    /// success while checking zero properties, which is the exact defect this
    /// work exists to remove. Returning nil falls back to the sentinel, whose
    /// zero trial count the renderer reports honestly.
    @Test("a body with no default marker relabels to nil rather than a silent pass")
    func relabelFailsClosed() {
        #expect(StrategistDispatchEmitter.edgePassBody(fromDefaultBody: "print(\"hello\")") == nil)
        #expect(StrategistDispatchEmitter.edgePassBody(fromDefaultBody: "") == nil)
    }

    @Test("the edge recipe draws only from the boundary set")
    func edgeRecipeDrawsOnlyBoundaries() throws {
        let base = StrategistDispatchEmitter.GeneratorRecipe(
            expression: "Gen<Int>.int()", carrierTypeName: "Int", imports: ["PropertyBased"]
        )
        let edge = try #require(StrategistDispatchEmitter.edgeRecipe(from: base))
        #expect(edge.expression.contains("Gen<Int?>.element(of:"))
        #expect(edge.expression.contains("Int.min"))
        // No random draw mixed in — Pass 2 is boundary-only by construction.
        #expect(!edge.expression.contains("Gen.frequency"))
        #expect(edge.carrierTypeName == "Int")
    }

    @Test("a carrier with no boundary set yields no edge recipe")
    func noEdgeRecipeForOtherCarriers() {
        let base = StrategistDispatchEmitter.GeneratorRecipe(
            expression: "Blob.gen()", carrierTypeName: "Blob", imports: []
        )
        #expect(StrategistDispatchEmitter.edgeRecipe(from: base) == nil)
    }
}
