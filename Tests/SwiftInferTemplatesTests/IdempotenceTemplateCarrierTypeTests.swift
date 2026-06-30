import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.149 — carrier/owner split. The idempotence template's `carrier`
/// (`Suggestion.carrier`) is the *owner* / call-site qualifier, while the
/// new `carrierType` (`Suggestion.carrierTypeName`) is the *generator*
/// carrier — the `T` in `f: T -> T` that the emitted `Gen<T>` must produce.
///
/// They diverge for a `static`/free function whose property flows through a
/// parameter (e.g. `static func normalize(_ s: String) -> String` on an
/// unrelated `enum Engine`): the call is `Engine.normalize(_:)` but the
/// generator is `Gen<String>`. For a method defined on the carrier they
/// coincide and `carrierTypeName == carrier`.
@Suite("IdempotenceTemplate — V1.149 carrier/owner split")
struct IdempotenceTemplateCarrierTypeTests {

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
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: containingTypeName,
            bodySignals: .empty
        )
    }

    @Test("static func on an unrelated owner: carrier = owner, carrierTypeName = T")
    func divergentOwnerAndCarrier() throws {
        let suggestion = try #require(
            IdempotenceTemplate.suggest(
                for: summary("normalize", paramType: "String", returnType: "String", containingTypeName: "Engine")
            )
        )
        #expect(suggestion.carrier == "Engine")          // call-site qualifier
        #expect(suggestion.carrierTypeName == "String")  // Gen<T> carrier
    }

    @Test("method defined on the carrier: carrierTypeName equals carrier (no-op)")
    func coincidentOwnerAndCarrier() throws {
        let suggestion = try #require(
            IdempotenceTemplate.suggest(
                for: summary("normalize", paramType: "Int", returnType: "Int", containingTypeName: "Int")
            )
        )
        #expect(suggestion.carrier == "Int")
        #expect(suggestion.carrierTypeName == "Int")
    }

    @Test("free function (no owner): carrier nil, carrierTypeName = T")
    func freeFunctionCarrierType() throws {
        let suggestion = try #require(
            IdempotenceTemplate.suggest(
                for: summary("normalize", paramType: "String", returnType: "String", containingTypeName: nil)
            )
        )
        #expect(suggestion.carrier == nil)
        #expect(suggestion.carrierTypeName == "String")
    }
}
