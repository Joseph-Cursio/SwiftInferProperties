import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.21.C — math-library forward-function pair veto on non-lifted
/// round-trip. Suppresses cross-product noise (forward × forward) while
/// preserving the canonical-inverse anchor pairs cycle-17 measured at
/// 7/7 = 100% accept (V1.20.C picks #5–#11).
@Suite("RoundTripTemplate — V1.21.C math-forward function pair veto")
struct RoundTripTemplateMathForwardVetoTests {

    private func mathPair(
        _ forward: String,
        _ reverse: String,
        type: String = "Complex"
    ) -> FunctionPair {
        let forwardSummary = FunctionSummary(
            name: forward,
            parameters: [Parameter(label: nil, internalName: "z", typeText: type, isInout: false)],
            returnTypeText: type,
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: type,
            bodySignals: .empty
        )
        let reverseSummary = FunctionSummary(
            name: reverse,
            parameters: [Parameter(label: nil, internalName: "z", typeText: type, isInout: false)],
            returnTypeText: type,
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 5, column: 1),
            containingTypeName: type,
            bodySignals: .empty
        )
        return FunctionPair(forward: forwardSummary, reverse: reverseSummary)
    }

    // MARK: - Veto fires on cross-product noise

    @Test("'exp × cosh' vetoes (cycle-17 #12 cross-product)")
    func expCoshVetoes() throws {
        let signal = RoundTripTemplate.mathForwardFunctionPairVeto(for: mathPair("exp", "cosh"))
        let veto = try #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("cross-product"))
    }

    @Test("'exp × sqrt' vetoes (cycle-17 #13)")
    func expSqrtVetoes() {
        #expect(RoundTripTemplate.mathForwardFunctionPairVeto(for: mathPair("exp", "sqrt"))?.isVeto == true)
    }

    @Test("'log × sqrt' vetoes (cycle-17 #14)")
    func logSqrtVetoes() {
        #expect(RoundTripTemplate.mathForwardFunctionPairVeto(for: mathPair("log", "sqrt"))?.isVeto == true)
    }

    @Test("'sin × cos' vetoes (forward-forward trig)")
    func sinCosVetoes() {
        #expect(RoundTripTemplate.mathForwardFunctionPairVeto(for: mathPair("sin", "cos"))?.isVeto == true)
    }

    @Test("'sinh × cosh' vetoes (forward-forward hyperbolic)")
    func sinhCoshVetoes() {
        #expect(RoundTripTemplate.mathForwardFunctionPairVeto(for: mathPair("sinh", "cosh"))?.isVeto == true)
    }

    // MARK: - Allowlist preserves canonical inverse pairs

    @Test("Cycle-17 7 canonical anchors (exp×log, cos×acos, etc.) preserve")
    func cycle17AnchorsPreserve() {
        let anchors: [(String, String)] = [
            ("exp", "log"),
            ("cosh", "acosh"),
            ("sinh", "asinh"),
            ("tanh", "atanh"),
            ("cos", "acos"),
            ("sin", "asin"),
            ("tan", "atan")
        ]
        for (forward, reverse) in anchors {
            #expect(
                RoundTripTemplate.mathForwardFunctionPairVeto(for: mathPair(forward, reverse)) == nil,
                "\(forward) × \(reverse) should NOT veto (canonical inverse)"
            )
            #expect(
                RoundTripTemplate.mathForwardFunctionPairVeto(for: mathPair(reverse, forward)) == nil,
                "\(reverse) × \(forward) should NOT veto (orientation-insensitive)"
            )
        }
    }

    // MARK: - Veto requires both sides to be math-forward

    @Test("One-sided math name (math × non-math) does not veto")
    func oneSidedDoesNotVeto() {
        // 'exp' is math-forward; 'normalize' isn't. Pair veto requires both.
        #expect(RoundTripTemplate.mathForwardFunctionPairVeto(for: mathPair("exp", "normalize")) == nil)
    }

    @Test("Both non-math names do not veto")
    func bothNonMathDoesNotVeto() {
        #expect(RoundTripTemplate.mathForwardFunctionPairVeto(for: mathPair("encode", "decode")) == nil)
    }

    // MARK: - Veto requires (T) -> T shape

    @Test("Asymmetric type-shape (T) -> U does not veto even with curated names")
    func asymmetricShapeDoesNotVeto() {
        // 'exp' as a Complex -> Double encoder shape — even though 'exp'
        // is curated, the shape isn't (T) -> T so the veto skips.
        let forwardSummary = FunctionSummary(
            name: "exp",
            parameters: [Parameter(label: nil, internalName: "z", typeText: "Complex", isInout: false)],
            returnTypeText: "Double",
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "Math",
            bodySignals: .empty
        )
        let reverseSummary = FunctionSummary(
            name: "log",
            parameters: [Parameter(label: nil, internalName: "x", typeText: "Double", isInout: false)],
            returnTypeText: "Complex",
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 5, column: 1),
            containingTypeName: "Math",
            bodySignals: .empty
        )
        #expect(RoundTripTemplate.mathForwardFunctionPairVeto(
            for: FunctionPair(forward: forwardSummary, reverse: reverseSummary)
        ) == nil)
    }

    // MARK: - End-to-end suggest()

    @Test("End-to-end: cross-product 'exp × cosh' suggestion is fully suppressed")
    func endToEndCrossProductSuppressed() {
        let suggestion = RoundTripTemplate.suggest(for: mathPair("exp", "cosh"))
        #expect(suggestion == nil, "V1.21.C should suppress exp × cosh round-trip claim")
    }

    @Test("End-to-end: canonical inverse 'exp × log' still surfaces with normal scoring")
    func endToEndExpLogPreserved() throws {
        let suggestion = try #require(RoundTripTemplate.suggest(for: mathPair("exp", "log")))
        #expect(suggestion.templateName == "round-trip")
        // Score should NOT reflect a math-forward veto (would be Suppressed
        // if it did). Type-symmetry signal fires (+30) at minimum.
        #expect(suggestion.score.tier != .suppressed)
    }
}
