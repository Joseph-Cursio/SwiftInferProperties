import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// Helpers live in an extension so the primary suite body stays under
// SwiftLint's `type_body_length` cap (extension bodies are exempt).
extension FunctionPairingTests {

    func makePair(
        forwardGroup: String?,
        reverseGroup: String?
    ) -> FunctionPair {
        let forward = makeSummary(
            name: "encode",
            returnType: "Data",
            paramType: "MyType",
            line: 3,
            discoverableGroup: forwardGroup
        )
        let reverse = makeSummary(
            name: "decode",
            returnType: "MyType",
            paramType: "Data",
            line: 7,
            discoverableGroup: reverseGroup
        )
        return FunctionPair(forward: forward, reverse: reverse)
    }

    func makeSummary(
        name: String,
        returnType: String?,
        paramType: String? = nil,
        parameters explicitParameters: [Parameter]? = nil,
        isMutating: Bool = false,
        isStatic: Bool = false,
        isInitializer: Bool = false,
        containingType: String? = nil,
        file: String = "Test.swift",
        line: Int = 1,
        discoverableGroup: String? = nil
    ) -> FunctionSummary {
        let parameters: [Parameter]
        if let explicitParameters {
            parameters = explicitParameters
        } else if let paramType {
            parameters = [Parameter(label: nil, internalName: "value", typeText: paramType, isInout: false)]
        } else {
            parameters = []
        }
        return FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: isMutating,
            isStatic: isStatic,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: containingType,
            bodySignals: .empty,
            discoverableGroup: discoverableGroup,
            isInitializer: isInitializer
        )
    }
}
