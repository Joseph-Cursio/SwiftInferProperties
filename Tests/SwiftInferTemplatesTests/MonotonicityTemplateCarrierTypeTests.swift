import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.151 (WS-1) — monotonicity carrier/owner split. `carrier`
/// (`Suggestion.carrier`) is the call-site owner; `carrierTypeName`
/// (`Suggestion.carrierTypeName`) is the *generator* domain — the input
/// parameter type the monotonic relation quantifies over. For an instance
/// method `func f(_ x: P) -> C` on `Owner`, the call qualifier is `Owner` but
/// the emitted `Gen<...>` must produce `P`, not `Owner`. Before WS-1 the
/// carrier fell back to `typeName` (the owner), so verify dead-ended deriving
/// a generator for the receiver type instead of the input domain.
@Suite("MonotonicityTemplate — WS-1 carrier/owner split")
struct MonotonicityTemplateCarrierTypeTests {

    private func summary(
        _ name: String,
        paramType: String,
        returnType: String,
        containingTypeName: String?
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "x", typeText: paramType, isInout: false)],
            returnTypeText: returnType,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: containingTypeName,
            bodySignals: .empty
        )
    }

    @Test("instance method: carrier = owner, carrierTypeName = input param domain")
    func divergentOwnerAndParam() throws {
        // Mirrors SQLiteStatement.columnDouble(at: Int) -> Double from the
        // road-test: the receiver is SQLiteStatement, but the monotonic input
        // domain is the `at:` index.
        let suggestion = try #require(
            MonotonicityTemplate.suggest(
                for: summary(
                    "columnDouble",
                    paramType: "Int",
                    returnType: "Double",
                    containingTypeName: "SQLiteStatement"
                )
            )
        )
        #expect(suggestion.carrier == "SQLiteStatement")  // call-site owner
        #expect(suggestion.carrierTypeName == "Int")       // Gen<Param> domain
    }

    @Test("free function: carrier nil, carrierTypeName = input param domain")
    func freeFunctionCarrierType() throws {
        let suggestion = try #require(
            MonotonicityTemplate.suggest(
                for: summary(
                    "scale",
                    paramType: "Double",
                    returnType: "Double",
                    containingTypeName: nil
                )
            )
        )
        #expect(suggestion.carrier == nil)
        #expect(suggestion.carrierTypeName == "Double")
    }
}
