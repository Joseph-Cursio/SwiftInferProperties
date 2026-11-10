import SwiftInferCore
@testable import SwiftInferTemplates

// Shared builders for the CommutativityTemplate test suites. Extracted (and made
// internal) so `CommutativityTemplateTests` and `CommutativityTemplateShapeTests`
// share one definition and the primary file stays under SwiftLint's file_length
// cap. The `docComment` param feeds the docstring-corroboration tests.
func makeCommutativitySummary(
    name: String,
    returnType: String?,
    paramTypes: (String, String)? = nil,
    parameters explicitParameters: [Parameter]? = nil,
    isMutating: Bool = false,
    containingType: String? = nil,
    bodySignals: BodySignals = .empty,
    docComment: String? = nil
) -> FunctionSummary {
    let parameters: [Parameter]
    if let explicitParameters {
        parameters = explicitParameters
    } else if let paramTypes {
        parameters = [
            Parameter(label: nil, internalName: "lhs", typeText: paramTypes.0, isInout: false),
            Parameter(label: nil, internalName: "rhs", typeText: paramTypes.1, isInout: false),
        ]
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
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 1, column: 1),
        containingTypeName: containingType,
        bodySignals: bodySignals,
        docComment: docComment
    )
}

func makeCommutativitySummary(
    name: String,
    parameters: [Parameter],
    returnType: String?
) -> FunctionSummary {
    makeCommutativitySummary(
        name: name,
        returnType: returnType,
        paramTypes: nil,
        parameters: parameters,
        isMutating: false,
        bodySignals: .empty
    )
}
