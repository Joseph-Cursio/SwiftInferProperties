import Testing
import SwiftInferCore

// V1.16.1 — Tests for the hoisted SetAlgebraShape.isSelfTypedBinaryOp(_:)
// helper. Hoisted from InversePairSetAlgebraShapeGate.swift's private
// helper when round-trip + idempetence became consumers (second-
// consumer-triggers-hoist pattern from v1.13).

@Suite("SetAlgebraShape.isSelfTypedBinaryOp — V1.16.1 hoisted helper")
struct SetAlgebraShapeHelperTests {

    @Test("V1.16.1 — Self -> Self returns true")
    func selfToSelfReturnsTrue() {
        let summary = makeSummary(paramType: "Self", returnType: "Self")
        #expect(SetAlgebraShape.isSelfTypedBinaryOp(summary))
    }

    @Test("V1.16.1 — non-Self param type returns false")
    func nonSelfParamReturnsFalse() {
        let summary = makeSummary(paramType: "Int", returnType: "Self")
        #expect(!SetAlgebraShape.isSelfTypedBinaryOp(summary))
    }

    @Test("V1.16.1 — non-Self return type returns false")
    func nonSelfReturnReturnsFalse() {
        let summary = makeSummary(paramType: "Self", returnType: "Int")
        #expect(!SetAlgebraShape.isSelfTypedBinaryOp(summary))
    }

    @Test("V1.16.1 — both non-Self returns false")
    func bothNonSelfReturnsFalse() {
        let summary = makeSummary(paramType: "Int", returnType: "Int")
        #expect(!SetAlgebraShape.isSelfTypedBinaryOp(summary))
    }

    @Test("V1.16.1 — empty parameters returns false")
    func emptyParametersReturnsFalse() {
        let summary = FunctionSummary(
            name: "noop",
            parameters: [],
            returnTypeText: "Self",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        #expect(!SetAlgebraShape.isSelfTypedBinaryOp(summary))
    }

    @Test("V1.16.1 — case-sensitive: 'self' (lowercase) returns false")
    func caseSensitive() {
        let summary = makeSummary(paramType: "self", returnType: "self")
        #expect(!SetAlgebraShape.isSelfTypedBinaryOp(summary))
    }

    @Test("V1.16.1 — helper lives in SwiftInferCore (canonical post-cycle-13)")
    func helperLivesInCore() {
        // The function exists at SwiftInferCore.SetAlgebraShape.isSelfTypedBinaryOp.
        // Compile-time assertion: the symbol resolves through the core module.
        let summary = makeSummary(paramType: "Self", returnType: "Self")
        let _: Bool = SetAlgebraShape.isSelfTypedBinaryOp(summary)
    }

    private func makeSummary(paramType: String, returnType: String) -> FunctionSummary {
        FunctionSummary(
            name: "intersection",
            parameters: [Parameter(label: nil, internalName: "other", typeText: paramType, isInout: false)],
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }
}
