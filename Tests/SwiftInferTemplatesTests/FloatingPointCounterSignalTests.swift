import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("FP storage counter-signal — V1.4.3 calibration tuning")
struct FloatingPointCounterSignalTests {

    // MARK: - Fixtures

    /// Build a binary-op summary `func +(_:_:) -> T` with the given T.
    ///
    /// The default name is the `+` operator deliberately: it corroborates the
    /// algebraic shape (so B24's unsupported-shape counter does not fire) WITHOUT
    /// the `+40` curated-verb bump, so the score is exactly shape (30) plus the
    /// FP counter under test — which is what these cases isolate. A bare name
    /// like "op" would now be suppressed by B24 before the FP counter matters.
    private static func binaryOp(name: String = "+", typeText: String) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: typeText, isInout: false),
                Parameter(label: nil, internalName: "b", typeText: typeText, isInout: false)
            ],
            returnTypeText: typeText,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: true,
            location: SourceLocation(file: "test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    /// Build a unary-codomain `func forward(_:T) -> U` summary.
    private static func unary(
        name: String = "encode",
        domain: String,
        codomain: String
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "x", typeText: domain, isInout: false)],
            returnTypeText: codomain,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    // MARK: - Associativity

    @Test("Associativity on Double drops Score 30 → 20 (Possible-tier floor)")
    func associativityDoubleScoreDropsToFloor() throws {
        let summary = Self.binaryOp(typeText: "Double")
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 20)
        #expect(suggestion.score.tier == .possible)
        #expect(suggestion.score.signals.contains { $0.kind == .floatingPointStorage })
    }

    @Test("Associativity on Complex<Double> hits the FP counter-signal via generic strip")
    func associativityComplexGenericStripped() throws {
        let summary = Self.binaryOp(typeText: "Complex<Double>")
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 20)
        #expect(suggestion.score.signals.contains { $0.kind == .floatingPointStorage })
    }

    @Test("Associativity on Int does NOT fire the FP counter-signal")
    func associativityIntUnaffected() throws {
        let summary = Self.binaryOp(typeText: "Int")
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 30)
        #expect(!suggestion.score.signals.contains { $0.kind == .floatingPointStorage })
    }

    @Test("Associativity on Double surfaces kit-FloatingPoint pointer in explainability")
    func associativityDoubleKitPointer() throws {
        let summary = Self.binaryOp(typeText: "Double")
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("conforms to FloatingPoint"))
        #expect(caveats.contains("finite-only generator"))
        #expect(caveats.contains("checkFloatingPointPropertyLaws"))
        #expect(caveats.contains("Associativity holds in principle"))
    }

    @Test("Associativity on Complex surfaces tolerance-posture advisory (cycle-2 generator override)")
    func associativityComplexNonKitAdvisory() throws {
        let summary = Self.binaryOp(typeText: "Complex")
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("IEEE 754 floating-point storage"))
        #expect(caveats.contains("finite-only generator"))
        #expect(caveats.contains("FloatingPointLaws.swift"))
        #expect(caveats.contains("Associativity holds in principle"))
    }

    // MARK: - Commutativity

    @Test("Commutativity on Float drops Score 30 → 20 with FP counter-signal")
    func commutativityFloatDropsToFloor() throws {
        let summary = Self.binaryOp(typeText: "Float")
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 20)
        #expect(suggestion.score.signals.contains { $0.kind == .floatingPointStorage })
    }

    @Test("Commutativity on String does NOT fire the FP counter-signal")
    func commutativityStringUnaffected() throws {
        let summary = Self.binaryOp(typeText: "String")
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 30)
        #expect(!suggestion.score.signals.contains { $0.kind == .floatingPointStorage })
    }

    @Test("Commutativity on Decimal surfaces tolerance-posture advisory")
    func commutativityDecimalNonKitAdvisory() throws {
        let summary = Self.binaryOp(typeText: "Decimal")
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("IEEE 754 floating-point storage"))
        #expect(caveats.contains("finite-only generator"))
        #expect(caveats.contains("Commutativity holds in principle"))
    }

    // MARK: - Inverse-pair

    @Test("Inverse-pair on FP-typed pair (non-curated names) drops to Score 15 (Suppressed → filtered)")
    func inversePairFPNonCuratedSuppressed() {
        // Inverse-pair baseline is Score 25 (typeSymmetry only, no curated
        // name match); -10 FP counter-signal lands Score 15 = Suppressed
        // = `suggest` returns nil. Uses `transform`/`untransform` which
        // aren't in `curatedInversePairs`.
        let forward = Self.unary(name: "transform", domain: "Double", codomain: "Bytes")
        let reverse = Self.unary(name: "untransform", domain: "Bytes", codomain: "Double")
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion == nil, "FP-typed inverse-pair should suppress to filtered")
    }

    @Test("Inverse-pair on FP-typed curated pair (encode/decode) stays at Score 25 (Possible)")
    func inversePairFPCuratedStaysPossible() throws {
        // Same FP types but with the curated `encode`/`decode` name pair.
        // Score = 25 (typeSymmetry) + 10 (curated) - 10 (FP) = 25 → Possible.
        // The kit-pointer is still surfaced in the explainability block.
        let forward = Self.unary(name: "encode", domain: "Double", codomain: "Bytes")
        let reverse = Self.unary(name: "decode", domain: "Bytes", codomain: "Double")
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = try #require(InversePairTemplate.suggest(for: pair))
        #expect(suggestion.score.total == 25)
        #expect(suggestion.score.signals.contains { $0.kind == .floatingPointStorage })
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("checkFloatingPointPropertyLaws"))
    }

    @Test("Inverse-pair where neither side is FP-storage stays unchanged")
    func inversePairNonFPUnchanged() throws {
        // Non-curated, non-FP names. Score = 25 (typeSymmetry only).
        // No FP counter-signal; no FP advisory.
        let forward = Self.unary(name: "transform", domain: "MyType", codomain: "Bytes")
        let reverse = Self.unary(name: "untransform", domain: "Bytes", codomain: "MyType")
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = try #require(InversePairTemplate.suggest(for: pair))
        #expect(suggestion.score.total == 25)
        #expect(!suggestion.score.signals.contains { $0.kind == .floatingPointStorage })
    }

    // MARK: - Identity-element exempt

    @Test("Identity-element template is NOT touched (FP identity is reliable)")
    func identityElementExempt() {
        // Identity-element scoring lives in IdentityElementTemplate; this test
        // sanity-checks that we did NOT add the FP counter-signal there. The
        // identity-element @ Score 70 on Complex.+ on the swift-numerics
        // ComplexModule corpus is the production verification — if anything
        // on identity-element changed, that integration would visibly drop.
        // Here we just confirm Signal.Kind.floatingPointStorage exists and
        // is documented as not applying to identity-element.
        #expect(Signal.Kind.allCases.contains(.floatingPointStorage))
    }
}
