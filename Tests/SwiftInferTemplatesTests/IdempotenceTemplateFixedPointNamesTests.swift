import PropertyLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

/// V1.22.C — fixed-point-name positive signal on non-lifted
/// idempotence. **First recall-positive signal in the post-V1.4.3
/// era** (all prior cycles shipped suppression-only mechanisms).
/// Mechanism class 14 in the cycle-19 taxonomy.
///
/// Score arithmetic at v1.22:
/// - typeSymmetry (+30) + carrier (+5) + fixed-point (+10) = +45 → Likely
///   (was +35 → Possible at v1.21).
/// - typeSymmetry (+30) + curated verb (+40, V1.4.1) + carrier (+5) +
///   fixed-point (+10) = +85 → Strong (only applies if FixedPointNames
///   and curatedVerbs overlap; current sets don't overlap by design).
@Suite("IdempotenceTemplate — V1.22.C fixed-point-name positive signal")
struct IdempotenceTemplateFixedPointNamesTests {

    private func summary(
        _ name: String,
        carrierType: String = "Polynomial"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "v", typeText: carrierType, isInout: false)],
            returnTypeText: carrierType,
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrierType,
            bodySignals: .empty
        )
    }

    private func valueSemanticResolver(carrier: String = "Polynomial") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "coefficients", typeName: "[Double]")]
            )
        ])
    }

    // MARK: - Curated set membership

    @Test("FixedPointNames.curated contains the v1.22 fixed-point name set")
    func curatedSetMembership() {
        for name in ["dedupe", "simplify", "clamp", "truncate", "standardize"] {
            #expect(FixedPointNames.curated.contains(name), "\(name) should be in curated set")
        }
    }

    @Test("FixedPointNames.curated does NOT overlap with IdempotenceTemplate.curatedVerbs")
    func noCuratedVerbsOverlap() {
        // Design constraint: V1.22.C set excludes V1.4.1 overlap because
        // overlap names are already at +40 → Strong tier; redundant +10
        // doesn't change tier. Set focuses on names not in V1.4.1.
        let overlap = FixedPointNames.curated.intersection(IdempotenceTemplate.curatedVerbs)
        #expect(overlap.isEmpty, "FixedPointNames.curated overlaps with curatedVerbs: \(overlap)")
    }

    // MARK: - Signal fires on curated names

    @Test("'dedupe' fires +10 fixed-point signal")
    func dedupeFires() throws {
        let signal = IdempotenceTemplate.fixedPointNameSignal(for: summary("dedupe"))
        let fixedPoint = try #require(signal)
        #expect(fixedPoint.weight == 10)
        #expect(fixedPoint.kind == .fixedPointName)
        #expect(fixedPoint.detail.contains("'dedupe'"))
        #expect(fixedPoint.detail.contains("idempotent"))
    }

    @Test("All 5 curated fixed-point names fire +10")
    func allCuratedFire() {
        for name in FixedPointNames.curated {
            let signal = IdempotenceTemplate.fixedPointNameSignal(for: summary(name))
            #expect(signal?.weight == 10, "Expected +10 for '\(name)'")
        }
    }

    // MARK: - Signal does NOT fire on non-curated names

    @Test("'normalize' (in V1.4.1 curatedVerbs, NOT in FixedPointNames) does not fire fixed-point signal")
    func normalizeDoesNotFireFixedPoint() {
        // 'normalize' fires V1.4.1 nameSignal at +40, but the V1.22.C
        // FixedPointNames set is intentionally distinct (no overlap).
        #expect(IdempotenceTemplate.fixedPointNameSignal(for: summary("normalize")) == nil)
    }

    @Test("'someRandomName' fires neither V1.4.1 curated nor V1.22.C fixed-point")
    func arbitraryNameFiresNothing() {
        #expect(IdempotenceTemplate.fixedPointNameSignal(for: summary("someRandomName")) == nil)
    }

    // MARK: - End-to-end recall-positive movement

    @Test("End-to-end: 'simplify' on Polynomial earns Likely (was Possible pre-V1.22.C)")
    func simplifyOnPolynomialIsLikely() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            for: summary("simplify"),
            carrierKindResolver: valueSemanticResolver()
        ))
        // 30 typeSymmetry + 5 carrier + 10 fixed-point = +45 → Likely.
        #expect(suggestion.score.total == 45)
        #expect(suggestion.score.tier == .likely)
        // Verify the fixed-point signal is in the explainability block.
        let hasFixedPointLine = suggestion.explainability.whySuggested.contains {
            $0.contains("Fixed-point name 'simplify'")
        }
        #expect(hasFixedPointLine, "Expected fixed-point signal in whySuggested")
    }

    @Test("End-to-end: 'normalize' on Polynomial still earns Strong (V1.4.1 path; V1.22.C does NOT add)")
    func normalizeOnPolynomialIsStrong() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            for: summary("normalize"),
            carrierKindResolver: valueSemanticResolver()
        ))
        // 30 typeSymmetry + 40 V1.4.1 curated + 5 carrier = +75 → Strong.
        // V1.22.C does NOT fire (normalize not in FixedPointNames).
        #expect(suggestion.score.total == 75)
        #expect(suggestion.score.tier == .strong)
    }

    @Test("End-to-end: 'someRandomName' on Polynomial stays Possible (no curated match)")
    func arbitraryNameStaysPossible() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            for: summary("someRandomName"),
            carrierKindResolver: valueSemanticResolver()
        ))
        // 30 typeSymmetry + 5 carrier = +35 → Possible.
        #expect(suggestion.score.total == 35)
        #expect(suggestion.score.tier == .possible)
    }

    @Test("Signal-pipeline integration: V1.22.C signal appears alongside other signals")
    func signalPipelineIntegration() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            for: summary("clamp"),
            carrierKindResolver: valueSemanticResolver()
        ))
        // Score arithmetic: 30 + 5 + 10 = 45.
        #expect(suggestion.score.total == 45)
        // The suggestion's explainability whySuggested must include the
        // fixed-point line in the signal-pipeline order.
        let lines = suggestion.explainability.whySuggested
        let fixedPointIndex = lines.firstIndex(where: { $0.contains("Fixed-point name") })
        #expect(fixedPointIndex != nil, "Fixed-point signal should be in whySuggested")
    }
}
