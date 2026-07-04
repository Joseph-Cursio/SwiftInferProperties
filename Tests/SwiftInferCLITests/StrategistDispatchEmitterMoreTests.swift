import Foundation
import PropertyLawCore
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

// Continuation of StrategistDispatchEmitter tests — signal-driven instance-method
// shapes and Cycle 149 dual-style-consistency coverage. Kept in a sibling file to
// satisfy the file_length cap on the primary test file.

@Suite("StrategistDispatchEmitter — signal-driven + Cycle 149 emit dispatch")
struct DispatchEmitterExtendedTests {

    private static let canonicalSeed = StrategistDispatchEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    private static func inputs(
        template: String,
        carrier: String = "Int",
        functionCalls: [String] = ["{ (x: Int) in x }"],
        trialBudget: StrategistDispatchEmitter.TrialBudget = .small,
        isInstanceMethod: Bool = false,
        isMutatingMethod: Bool = false,
        isNullary: Bool = false,
        returnsSelfType: Bool = false
    ) -> StrategistDispatchEmitter.Inputs {
        StrategistDispatchEmitter.Inputs(
            carrier: carrier,
            typeShape: nil,
            template: template,
            functionCalls: functionCalls,
            extraImports: [],
            seedHex: canonicalSeed,
            trialBudget: trialBudget,
            isInstanceMethod: isInstanceMethod,
            isMutatingMethod: isMutatingMethod,
            isNullary: isNullary,
            returnsSelfType: returnsSelfType
        )
    }

    // Instance-method idempotence driven by the SemanticIndex callee-shape
    // signal (generalizes V1.60.A off the hardcoded OC carrier set).

    @Test("signal-driven mutating idempotence emits the receiver shape on a non-OC carrier")
    func signalDrivenMutatingIdempotenceOnNonOCCarrier() throws {
        // String is NOT in mutatingInstanceCarriers — the mutating shape
        // fires solely because the callee-shape signal says so.
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "idempotence",
                carrier: "String",
                functionCalls: ["String.normalizeInPlace"],
                isInstanceMethod: true,
                isMutatingMethod: true,
                isNullary: true
            )
        )
        #expect(source.contains("var onceCopy = value"))
        #expect(source.contains("onceCopy.normalizeInPlace()"))
        #expect(source.contains("twiceCopy.normalizeInPlace()"))
        // The static shape must not appear.
        #expect(source.contains("String.normalizeInPlace(value)") == false)
    }

    @Test("signal-driven self-returning idempotence chains the method on the receiver")
    func signalDrivenSelfReturningIdempotence() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "idempotence",
                carrier: "String",
                functionCalls: ["String.trimmedCopy"],
                isInstanceMethod: true,
                isMutatingMethod: false,
                isNullary: true,
                returnsSelfType: true
            )
        )
        #expect(source.contains("let onceResult = value.trimmedCopy()"))
        #expect(source.contains("let twiceResult = onceResult.trimmedCopy()"))
        // Neither the static shape nor the mutating shape.
        #expect(source.contains("String.trimmedCopy(value)") == false)
        #expect(source.contains("var onceCopy") == false)
    }

    @Test("Cycle 149 (Lever C-1): dual-style merge on OrderedDictionary emits the uniquing closure on both halves")
    func dualStyleMergeEmitsUniquingClosure() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "dual-style-consistency",
                carrier: "OrderedDictionary<Int, Int>",
                functionCalls: ["OrderedDictionary.merging", "merge"]
            )
        )
        let closure = ", uniquingKeysWith: { (_, new) in new }"
        // Both halves must carry the SAME conflict closure so the
        // dual-style equivalence holds.
        #expect(source.contains("original.merging(other\(closure))"))
        #expect(source.contains("mutCopy.merge(other\(closure))"))
    }

    @Test("Cycle 149 (Lever C-1): dual-style SetAlgebra union takes no trailing closure (regression guard)")
    func dualStyleUnionNoTrailingClosure() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "dual-style-consistency",
                carrier: "OrderedSet<Int>",
                functionCalls: ["OrderedSet.union", "formUnion"]
            )
        )
        #expect(source.contains("original.union(other)"))
        #expect(source.contains("mutCopy.formUnion(other)"))
        #expect(source.contains("uniquingKeysWith") == false)
    }

    @Test("Cycle 149 (Lever C-1): dualStyleTrailingArgument keyed on mutating method name")
    func dualStyleTrailingArgumentLookup() {
        #expect(StrategistDispatchEmitter.dualStyleTrailingArgument(forMutating: "merge")
            == ", uniquingKeysWith: { (_, new) in new }")
        #expect(StrategistDispatchEmitter.dualStyleTrailingArgument(forMutating: "formUnion").isEmpty)
        #expect(StrategistDispatchEmitter.dualStyleTrailingArgument(forMutating: "sort").isEmpty)
    }
}
