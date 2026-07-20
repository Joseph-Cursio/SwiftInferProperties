import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Case 7 Part 2 — the synthetic codec *decode* summaries built from struct
/// initializers so an instance-method encode can pair with an `init?` decode.
@Suite("InitializerDecodeSynthesizer — codec decode from struct inits")
struct InitializerDecodeSynthesizerTests {

    private static let loc = SourceLocation(file: "Blob.swift", line: 1, column: 1)

    private func structDecl(
        _ name: String,
        initializers: [InitializerSignature]
    ) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: .struct,
            inheritedTypes: [],
            location: Self.loc,
            initializers: initializers
        )
    }

    private func initSig(
        _ label: String?,
        _ type: String,
        isFailable: Bool = false,
        isThrowing: Bool = false
    ) -> InitializerSignature {
        InitializerSignature(
            parameters: [InitializerParameter(label: label, typeName: type)],
            isFailable: isFailable,
            isThrowing: isThrowing
        )
    }

    @Test("a single-parameter init becomes a `paramType -> Self` decode named after its label")
    func singleParamInitSynthesized() throws {
        let decl = structDecl("Blob", initializers: [initSig("base64Encoded", "String", isFailable: true)])
        let summaries = InitializerDecodeSynthesizer.summaries(from: [decl])
        let decode = try #require(summaries.first)
        #expect(summaries.count == 1)
        #expect(decode.name == "base64Encoded")
        #expect(decode.parameters.first?.typeText == "String")
        #expect(decode.returnTypeText == "Blob")           // bare Self — the type-shape match
        #expect(decode.containingTypeName == "Blob")
        #expect(decode.isInitializer)
    }

    @Test("a multi-parameter (memberwise) init is NOT synthesized — it is not a decode")
    func multiParamInitSkipped() {
        let memberwise = InitializerSignature(
            parameters: [
                InitializerParameter(label: "x", typeName: "Int"),
                InitializerParameter(label: "y", typeName: "Int")
            ]
        )
        let decl = structDecl("Point", initializers: [memberwise])
        #expect(InitializerDecodeSynthesizer.summaries(from: [decl]).isEmpty)
    }

    @Test("only structs contribute init-decodes")
    func onlyStructs() {
        let enumDecl = TypeDecl(
            name: "E", kind: .enum, inheritedTypes: [], location: Self.loc,
            initializers: [initSig("raw", "Int")]
        )
        #expect(InitializerDecodeSynthesizer.summaries(from: [enumDecl]).isEmpty)
    }

    @Test("an unlabelled init synthesizes to the bare name \"init\" (no stem to match)")
    func unlabelledInit() throws {
        let decl = structDecl("Blob", initializers: [initSig(nil, "String")])
        let decode = try #require(InitializerDecodeSynthesizer.summaries(from: [decl]).first)
        #expect(decode.name == "init")
    }
}
