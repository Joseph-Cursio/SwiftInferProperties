import PropertyLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

/// V1.21.C — math-library forward-function veto on non-lifted
/// idempotence. Cycle-17 V1.20.C picks #18, #19, #20 measured 0/3 = 0%
/// rejection on `exp` / `log` / `sqrt` non-lifted idempotence; this
/// suite verifies the veto fires on those + their family members.
@Suite("IdempotenceTemplate — V1.21.C math-forward function veto")
struct IdempotenceTemplateMathForwardVetoTests {

    private func mathSummary(
        _ name: String,
        carrierType: String = "Complex"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "z", typeText: carrierType, isInout: false)],
            returnTypeText: carrierType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrierType,
            bodySignals: .empty
        )
    }

    // MARK: - Veto fires on (T) -> T math-forward functions

    @Test("'exp' vetoes (cycle-17 #18 rate-stability)")
    func expVetoes() throws {
        let signal = IdempotenceTemplate.mathForwardFunctionVeto(for: mathSummary("exp"))
        let veto = try #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("'exp'"))
        #expect(veto.detail.contains("not idempotent"))
    }

    @Test("'log' vetoes (cycle-17 #19)")
    func logVetoes() {
        #expect(IdempotenceTemplate.mathForwardFunctionVeto(for: mathSummary("log"))?.isVeto == true)
    }

    @Test("'sqrt' vetoes (cycle-17 #20)")
    func sqrtVetoes() {
        #expect(IdempotenceTemplate.mathForwardFunctionVeto(for: mathSummary("sqrt"))?.isVeto == true)
    }

    @Test("All elementary-functions families veto on (T) -> T shape")
    func allFamiliesVeto() {
        let names = ["exp", "exp2", "expMinusOne", "log", "log2", "log10",
                     "sin", "cos", "tan", "asin", "acos", "atan",
                     "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
                     "sqrt", "cbrt"]
        for name in names {
            let signal = IdempotenceTemplate.mathForwardFunctionVeto(for: mathSummary(name))
            #expect(signal?.isVeto == true, "\(name) should veto on (T) -> T shape")
        }
    }

    // MARK: - Veto does NOT fire on non-curated names

    @Test("Non-curated name 'normalize' does not veto")
    func normalizeNotVetoed() {
        #expect(IdempotenceTemplate.mathForwardFunctionVeto(for: mathSummary("normalize")) == nil)
    }

    @Test("Non-curated name 'abs' does not veto (abs IS idempotent)")
    func absNotVetoed() {
        #expect(IdempotenceTemplate.mathForwardFunctionVeto(for: mathSummary("abs")) == nil)
    }

    // MARK: - Veto requires (T) -> T shape

    @Test("Two-param function with curated name does not veto (shape mismatch)")
    func twoParamNotVetoed() {
        let summary = FunctionSummary(
            name: "atan2",
            parameters: [
                Parameter(label: nil, internalName: "y", typeText: "Double", isInout: false),
                Parameter(label: nil, internalName: "x", typeText: "Double", isInout: false)
            ],
            returnTypeText: "Double",
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "Math",
            bodySignals: .empty
        )
        #expect(IdempotenceTemplate.mathForwardFunctionVeto(for: summary) == nil)
    }

    @Test("Function with mismatched return type does not veto")
    func mismatchedReturnTypeNotVetoed() {
        let summary = FunctionSummary(
            name: "exp",
            parameters: [Parameter(label: nil, internalName: "z", typeText: "Complex", isInout: false)],
            returnTypeText: "Double", // Different from param type — not (T) -> T
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "Math",
            bodySignals: .empty
        )
        #expect(IdempotenceTemplate.mathForwardFunctionVeto(for: summary) == nil)
    }

    @Test("Mutating function with curated name does not veto (lifted path handles)")
    func mutatingNotVetoed() {
        let summary = FunctionSummary(
            name: "exp",
            parameters: [Parameter(label: nil, internalName: "z", typeText: "Complex", isInout: false)],
            returnTypeText: "Complex",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "Math",
            bodySignals: .empty
        )
        #expect(IdempotenceTemplate.mathForwardFunctionVeto(for: summary) == nil)
    }

    // MARK: - End-to-end suggest()

    @Test("End-to-end: 'exp' Complex -> Complex suggestion is fully suppressed")
    func endToEndExpSuppression() {
        let summary = mathSummary("exp")
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion == nil, "V1.21.C should suppress exp idempotence claim")
    }

    @Test("End-to-end: non-math 'normalize' (T) -> T still surfaces as Strong")
    func endToEndNormalizePreserved() throws {
        let summary = FunctionSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "v", typeText: "Vector", isInout: false)],
            returnTypeText: "Vector",
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "Vector",
            bodySignals: .empty
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        // 30 type-symmetry + 40 curated verb 'normalize' = 70 → Likely
        // (Strong threshold is ≥75 per Tier mapping). The point of this
        // test is that the suggestion surfaces — V1.21.C math-forward
        // veto must not fire false-positives on non-math curated names.
        #expect(suggestion.score.tier == .likely)
        #expect(suggestion.score.total == 70)
    }
}
