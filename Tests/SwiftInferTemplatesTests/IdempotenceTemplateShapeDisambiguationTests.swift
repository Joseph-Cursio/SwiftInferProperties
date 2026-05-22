import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.24.D — capacity-from-scale + formatter shape-disambiguation veto
/// on non-lifted `IdempotenceTemplate.suggest(for:)`. Direct cycle-20
/// finding closure (5-cycle-flat 0% idempotence non-lifted rate is
/// dominated by shape-coincidence patterns).
@Suite("IdempotenceTemplate — V1.24.D shape-disambiguation veto")
struct IdempotenceShapeDisambiguationTests {

    private func summary(
        _ name: String,
        paramLabel: String? = nil,
        paramType: String = "Int",
        returnType: String = "Int",
        carrier: String = "OrderedSet"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: paramLabel, internalName: "x", typeText: paramType, isInout: false)],
            returnTypeText: returnType,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    // MARK: - Pattern 1: capacity / scale domain conversion

    @Test("'_minimumCapacity(forScale:)' fires veto (cycle-20 case; name contains 'Capacity')")
    func minimumCapacityVetoes() throws {
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("_minimumCapacity", paramLabel: "forScale")
        )
        let veto = try #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("cross-domain Int conversion"))
    }

    @Test("'_maximumCapacity(forScale:)' fires veto")
    func maximumCapacityVetoes() {
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("_maximumCapacity", paramLabel: "forScale")
        )
        #expect(signal?.isVeto == true)
    }

    @Test("'_scale(forCapacity:)' fires veto (name 'scale' doesn't contain Capacity, but label does)")
    func scaleByCapacityVetoes() {
        // Reverse direction: scale-FROM-capacity. Name doesn't match
        // Capacity/Count prefix, but the `forCapacity:` label is the
        // domain-conversion signal.
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("_scale", paramLabel: "forCapacity")
        )
        #expect(signal?.isVeto == true)
    }

    @Test("'wordCount(forScale:)' fires veto (name contains 'Count')")
    func wordCountVetoes() {
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("wordCount", paramLabel: "forScale")
        )
        #expect(signal?.isVeto == true)
    }

    // MARK: - Pattern 1: negative cases

    @Test("'(String) -> String' shape does NOT fire pattern 1 (Int-only)")
    func nonIntShapeDoesNotFirePattern1() {
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("normalizeCount", paramLabel: "forScale",
                         paramType: "String", returnType: "String")
        )
        #expect(signal == nil, "Pattern 1 requires (Int) -> Int shape")
    }

    @Test("Capacity name without forScale/forCapacity label does NOT fire (requires both name AND label)")
    func capacityWithoutLabelDoesNotFire() {
        // V1.24.D requires BOTH name hit AND label hit (not OR). Without
        // forScale:/forCapacity: label, capacity-named functions don't
        // veto — avoids false positives on canonical `capacity` accessors.
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("getCapacity", paramLabel: nil)
        )
        #expect(signal == nil, "Without forScale/forCapacity label, veto must not fire")
    }

    @Test("'normalize(forScale:)' does NOT fire (V1.15.1 curated verb; pattern requires Capacity/Count/Scale token)")
    func normalizeForScaleDoesNotFire() {
        // forScale: label hit + (Int) -> Int shape, but 'normalize' name
        // doesn't contain Capacity/Count/Scale tokens. Veto requires
        // BOTH name hit AND label hit — prevents false positive on the
        // canonical idempotence verb.
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("normalize", paramLabel: "forScale")
        )
        #expect(signal == nil, "normalize is a V1.15.1 curated idempotence verb — must not veto")
    }

    // MARK: - Pattern 2: formatter

    @Test("'_description(type:)' fires veto (cycle-17/20 #16/#12 case)")
    func descriptionFormatterVetoes() throws {
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("_description", paramLabel: "type",
                         paramType: "String", returnType: "String")
        )
        let veto = try #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("formatter"))
    }

    @Test("'format(_:)' on enum fires veto (cycle-17/20 #18 case)")
    func formatVetoes() {
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("format", paramLabel: nil,
                         paramType: "CheckResult", returnType: "String")
        )
        #expect(signal?.isVeto == true)
    }

    @Test("'formatBuckets' fires veto (prefix 'format')")
    func formatBucketsVetoes() {
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("formatBuckets", paramLabel: nil,
                         paramType: "[String: Int]", returnType: "String")
        )
        #expect(signal?.isVeto == true)
    }

    // MARK: - Negative cases (must NOT fire)

    @Test("'normalize' (curated idempotence verb) does NOT fire")
    func normalizeDoesNotFire() {
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("normalize", paramType: "String", returnType: "String")
        )
        #expect(signal == nil, "normalize is a legitimate idempotent function — must not veto")
    }

    @Test("'simplify' (FixedPointNames curated) does NOT fire")
    func simplifyDoesNotFire() {
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("simplify", paramType: "Polynomial", returnType: "Polynomial")
        )
        #expect(signal == nil)
    }

    @Test("'clamp' (FixedPointNames curated) does NOT fire")
    func clampDoesNotFire() {
        let signal = IdempotenceTemplate.shapeDisambiguationVeto(
            for: summary("clamp", paramType: "Int", returnType: "Int")
        )
        #expect(signal == nil)
    }

    // MARK: - End-to-end suggest()

    @Test("End-to-end: '_minimumCapacity(forScale:)' idempotence is suppressed at v1.24.D")
    func endToEndCapacitySuppressed() {
        let suggestion = IdempotenceTemplate.suggest(
            for: summary("_minimumCapacity", paramLabel: "forScale"),
            carrierKindResolver: CarrierKindResolver(typeDecls: [
                TypeDecl(name: "OrderedSet", kind: .struct, inheritedTypes: [],
                         location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                         storedMembers: [StoredMember(name: "elements", typeName: "[Int]")])
            ])
        )
        #expect(suggestion == nil, "V1.24.D should suppress capacity-from-scale idempotence")
    }
}
