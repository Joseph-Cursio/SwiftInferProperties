import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

// V1.51.E — unit tests for the three mechanical fixes (V1.51.A
// carrier normalization + V1.51.B dual-style pair expansion +
// V1.51.C v1.48-template routing flip).

@Suite("V1.51.A — bare→qualified carrier normalization")
struct V1_51CanonicalizationTests {

    @Test("Complex bare name canonicalizes to Complex<Double>")
    func complexCanonicalizes() {
        #expect(GenericBindingResolver.resolve("Complex") == "Complex<Double>")
        #expect(GenericBindingResolver.bound("Complex") == "Complex<Double>")
    }

    @Test("unknown bare names pass through unchanged")
    func unknownBareNamesPassThrough() {
        #expect(GenericBindingResolver.resolve("ComplexFlex") == nil)
        #expect(GenericBindingResolver.bound("ComplexFlex") == "ComplexFlex")
        // Existing carriers still pass through:
        #expect(GenericBindingResolver.bound("Double") == "Double")
        #expect(GenericBindingResolver.bound("Int") == "Int")
        #expect(GenericBindingResolver.bound("String") == "String")
    }

    @Test("V1.47.D bindings still resolve (regression guard)")
    func priorBindingsStillResolve() {
        #expect(GenericBindingResolver.resolve("Base.Index") == "Int")
        #expect(GenericBindingResolver.resolve("Self.Element") == "Int")
        #expect(GenericBindingResolver.resolve("Iterator.Element") == "Int")
    }
}

@Suite("V1.51.B — DualStyleConsistencyPairResolver curated expansion")
struct V1_51DualStyleExpansionTests {

    private static func entry(primary: String, carrier: String = "OrderedSet") -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xABCD",
            templateName: "dual-style-consistency",
            typeName: carrier,
            score: 30,
            tier: "Possible",
            primaryFunctionName: primary,
            location: "/x.swift:1",
            firstSeenAt: "2026-05-12T00:00:00Z",
            lastSeenAt: "2026-05-12T00:00:00Z"
        )
    }

    // V1.61.A — cycle-27 picks capture the **mutating** name as
    // primaryFunctionName (e.g. `formUnion(_:)`); the resolver now
    // looks up by either field and returns the correct Swift
    // SetAlgebra pair: `intersection` (non-mut) ↔ `formIntersection`
    // (mut), etc.

    @Test("V1.61.A: formIntersection lookup returns intersection / formIntersection pair")
    func formIntersection() throws {
        let result = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "formIntersection(_:)")
        )
        #expect(result.nonMutCall == "OrderedSet.intersection")
        #expect(result.mutMethodName == "formIntersection")
    }

    @Test("V1.61.A: formUnion lookup returns union / formUnion pair")
    func formUnion() throws {
        let result = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "formUnion(_:)")
        )
        #expect(result.nonMutCall == "OrderedSet.union")
        #expect(result.mutMethodName == "formUnion")
    }

    @Test("V1.61.A: formSymmetricDifference lookup returns symmetricDifference / formSymmetricDifference")
    func formSymmetricDifference() throws {
        let result = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "formSymmetricDifference(_:)")
        )
        #expect(result.nonMutCall == "OrderedSet.symmetricDifference")
        #expect(result.mutMethodName == "formSymmetricDifference")
    }

    @Test("V1.61.A: subtract lookup returns subtracting / subtract pair")
    func subtract() throws {
        let result = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "subtract(_:)")
        )
        #expect(result.nonMutCall == "OrderedSet.subtracting")
        #expect(result.mutMethodName == "subtract")
    }

    @Test("V1.61.A: merging lookup returns merging / merge")
    func mergingFamily() throws {
        let mergingPair = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "merging(_:uniquingKeysWith:)", carrier: "OrderedDictionary")
        )
        #expect(mergingPair.nonMutCall == "OrderedDictionary.merging")
        #expect(mergingPair.mutMethodName == "merge")
    }

    @Test("v1.48 initial pairs still resolve (regression guard)")
    func v1_48InitialPairsStillResolve() throws {
        let sortPair = try DualStyleConsistencyPairResolver.resolve(
            Self.entry(primary: "sorted()", carrier: "Array")
        )
        #expect(sortPair.nonMutCall == "Array.sorted")
        #expect(sortPair.mutMethodName == "sort")
    }

    @Test("V1.61.A: curated table has 8 entries (3 v1.48 + 4 SetAlgebra + 1 merge)")
    func curatedTableSize() {
        // V1.61.A reduced from V1.51.B's 9 entries to 8: the old
        // `merge(_:uniquingKeysWith:) ↔ merge` self-pair was redundant
        // with `merging ↔ merge`; the SetAlgebra pairs corrected to
        // 4 entries (union/intersection/symmetricDifference/subtracting).
        #expect(DualStyleConsistencyPairResolver.curated.count == 8)
    }
}

@Suite("V1.51.C — v1.48 template routing flip (always strategist)")
struct V1_51RoutingFlipTests {

    private static func entry(
        template: String,
        carrier: String,
        primary: String = "doubled()"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xABCD",
            templateName: template,
            typeName: carrier,
            score: 30,
            tier: "Possible",
            primaryFunctionName: primary,
            location: "/x.swift:1",
            firstSeenAt: "2026-05-12T00:00:00Z",
            lastSeenAt: "2026-05-12T00:00:00Z"
        )
    }

    @Test("monotonicity × Double routes through strategist (not v1.46 hardcoded)")
    func monotonicityDoubleRoutesThroughStrategist() throws {
        // V1.51.C: pre-fix, monotonicity × Double matched
        // v1_46HardcodedCarriers and hit v1_46HardcodedBundle's
        // default branch → .unsupportedTemplate. Post-fix, the carrier
        // check now requires *both* carrier in v1_46HardcodedCarriers
        // AND template in v1_46HardcodedTemplates; monotonicity is
        // in the v1.48 set, so the entry routes to the strategist.
        // The strategist's `.rawRepresentable(.double)` recipe emits
        // a working stub. We exercise the routing by calling
        // buildStubBundle and asserting no error is thrown.
        let result = try SwiftInferCommand.Verify.buildStubBundle(
            entry: Self.entry(template: "monotonicity", carrier: "Double"),
            budget: .small
        )
        // Strategist-routed stub source references the carrier directly.
        #expect(result.source.contains("monotonicity"))
    }

    @Test("round-trip × Complex<Double> still routes to v1.46 hardcoded (regression guard)")
    func roundTripComplexStillHardcoded() throws {
        let result = try SwiftInferCommand.Verify.buildStubBundle(
            entry: Self.entry(
                template: "round-trip",
                carrier: "Complex<Double>",
                primary: "exp(_:)"
            ),
            budget: .small
        )
        // v1.46 hardcoded path emits the V1.43.B Complex<Double>
        // two-pass shape with `Gen<Complex<Double>>.edgeCaseBiased()`.
        #expect(result.source.contains("Gen<Complex<Double>>.edgeCaseBiased()"))
    }

    @Test("idempotence-lifted × Double routes through strategist")
    func idempotenceLiftedDoubleRoutesThroughStrategist() throws {
        // Similar to monotonicity — Double is a v1.46 carrier, but
        // idempotence-lifted is a v1.48 template, so it routes to the
        // strategist.
        let result = try SwiftInferCommand.Verify.buildStubBundle(
            entry: Self.entry(
                template: "idempotence-lifted",
                carrier: "Double",
                primary: "normalized()"
            ),
            budget: .small
        )
        #expect(result.source.contains("idempotence-lifted"))
    }
}
