import Foundation
import Testing

@testable import SwiftInferCLI

// V1.69 — unit tests for the OC instance-method monotonicity emit
// shape (`composeInstanceMethodMonotonicityPass`). The v1.48
// `min`/`max`-on-carrier + static-call shape hard-failed on OC
// collection carriers; the rework draws a receiver collection, draws
// two valid indices from its own index range, and asserts
// `receiver.index(after:)` / `receiver.index(before:)` is monotonic
// over the *indices* — see
// `docs/calibration-cycle-60-monotonicity-investigation.md`.

@Suite("StrategistDispatchEmitter — V1.69 OC instance-method monotonicity")
struct MonotonicityOCEmitterTests {

    private static let canonicalSeed = StrategistDispatchEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    private static func inputs(
        carrier: String,
        primaryFunctionName: String
    ) -> StrategistDispatchEmitter.Inputs {
        // Mirrors what `VerifyCommand+TemplateDispatch.resolveFunctionCalls`
        // produces for a monotonicity entry: [renderedStaticCall,
        // primaryFunctionName]. The renderedStaticCall is unused by the
        // OC composer beyond recovering the bare method name.
        let bareType = carrier.split(separator: "<").first.map(String.init) ?? carrier
        return StrategistDispatchEmitter.Inputs(
            carrier: carrier,
            typeShape: nil,
            template: "monotonicity",
            functionCalls: ["\(bareType).index", primaryFunctionName],
            extraImports: [],
            seedHex: canonicalSeed,
            trialBudget: .small
        )
    }

    // MARK: - index(after:)

    @Test("OrderedSet<Int> index(after:) emits the receiver-and-index shape")
    func orderedSetIndexAfterShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(carrier: "OrderedSet<Int>", primaryFunctionName: "index(after:)")
        )
        // Receiver drawn from the curated OC generator.
        #expect(source.contains("let receiver = defaultGenerator.run(using: &rng)"))
        // Indices drawn from the receiver's own index range.
        #expect(source.contains(
            "Gen<Int>.int(in: receiver.startIndex ... (receiver.endIndex - 1))"
        ))
        // Indices — not the carrier — are ordered with min/max.
        #expect(source.contains("let lowerIndex = min(firstIndex, secondIndex)"))
        #expect(source.contains("let upperIndex = max(firstIndex, secondIndex)"))
        // Instance-method call shape with the recovered labeled argument.
        #expect(source.contains("let resultA = receiver.index(after: lowerIndex)"))
        #expect(source.contains("let resultB = receiver.index(after: upperIndex)"))
        #expect(source.contains("if resultA > resultB {"))
        // The v1.48 carrier-Comparable shape is gone.
        #expect(!source.contains("min(firstDraw, secondDraw)"))
        #expect(!source.contains("OrderedSet.index(valueA)"))
    }

    @Test("OrderedDictionary<Int, Int>.Elements index(after:) emits the instance shape")
    func orderedDictionaryElementsIndexAfterShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                carrier: "OrderedDictionary<Int, Int>.Elements",
                primaryFunctionName: "index(after:)"
            )
        )
        #expect(source.contains("let resultA = receiver.index(after: lowerIndex)"))
        #expect(source.contains(
            "Generator<OrderedDictionary<Int, Int>.Elements, some SendableSequenceType>"
        ))
        #expect(!source.contains("min(firstDraw, secondDraw)"))
    }

    // MARK: - index(before:)

    @Test("index(before:) shifts the index domain to exclude startIndex")
    func indexBeforeDomain() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(carrier: "OrderedSet<Int>", primaryFunctionName: "index(before:)")
        )
        #expect(source.contains(
            "Gen<Int>.int(in: (receiver.startIndex + 1) ... receiver.endIndex)"
        ))
        #expect(source.contains("let resultA = receiver.index(before: lowerIndex)"))
        #expect(source.contains("let resultB = receiver.index(before: upperIndex)"))
        // `index(after:)`'s domain must not leak into the before path.
        #expect(!source.contains("(receiver.endIndex - 1)"))
    }

    // MARK: - Markers + Int-path non-regression

    @Test("OC monotonicity still emits the standard markers + single-pass")
    func ocMonotonicityMarkers() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(carrier: "OrderedSet<Int>", primaryFunctionName: "index(after:)")
        )
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"))
    }

    @Test("Int-carrier monotonicity is untouched — keeps the v1.48 min/max-on-value shape")
    func intCarrierKeepsValueShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "Int",
                typeShape: nil,
                template: "monotonicity",
                functionCalls: ["{ (x: Int) in x * 2 }", "scale(_:)"],
                extraImports: [],
                seedHex: Self.canonicalSeed,
                trialBudget: .small
            )
        )
        // The else-branch composer reads only functionCalls.first; the
        // appended primaryFunctionName is ignored.
        #expect(source.contains("let valueA = min(firstDraw, secondDraw)"))
        #expect(source.contains("{ (x: Int) in x * 2 }(valueA)"))
        #expect(!source.contains("receiver.index"))
    }

    // MARK: - V1.69.B nested-OC scaffolds

    @Test("nested-OC carriers emit the instance shape", arguments: [
        "OrderedSet<Int>.SubSequence",
        "OrderedDictionary<Int, Int>.Values",
        "OrderedDictionary<Int, Int>.Elements.SubSequence"
    ])
    func nestedOCCarrierEmitsInstanceShape(carrier: String) throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(carrier: carrier, primaryFunctionName: "index(after:)")
        )
        #expect(source.contains("Generator<\(carrier), some SendableSequenceType>"))
        #expect(source.contains("let resultA = receiver.index(after: lowerIndex)"))
        #expect(!source.contains("min(firstDraw, secondDraw)"))
    }

    @Test("the 3 nested-OC binding keys resolve to their bound forms")
    func nestedOCBindingsResolve() {
        #expect(
            GenericBindingResolver.resolve("OrderedSet.SubSequence")
                == "OrderedSet<Int>.SubSequence"
        )
        #expect(
            GenericBindingResolver.resolve("OrderedDictionary.Values")
                == "OrderedDictionary<Int, Int>.Values"
        )
        #expect(
            GenericBindingResolver.resolve("OrderedDictionary.Elements.SubSequence")
                == "OrderedDictionary<Int, Int>.Elements.SubSequence"
        )
    }

    // MARK: - Methodology guard

    @Test("every monotonicityInstanceCarrier resolves a curated OC recipe")
    func everyInstanceCarrierHasARecipe() throws {
        for carrier in StrategistDispatchEmitter.monotonicityInstanceCarriers {
            // resolveRecipe must not throw — every instance carrier needs
            // a curated OC recipe (the recipe produces the receiver).
            let recipe = try StrategistDispatchEmitter.resolveRecipe(
                carrier: carrier,
                typeShape: nil
            )
            #expect(recipe.carrierTypeName == carrier)
        }
    }
}
