import ProtoLawCore
import SwiftSyntax

extension FunctionScannerVisitor {

    /// Build a `FunctionSummary` from a `FunctionDeclSyntax`. Combines
    /// signature info (parameters / return / effects / modifiers), the
    /// `BodySignalVisitor` walk over the body, and the M5.3 + M7.2.a
    /// attribute scans for `@Discoverable(group:)` and
    /// `@CheckProperty(.preservesInvariant(\..))`.
    func makeSummary(from node: FunctionDeclSyntax) -> FunctionSummary {
        let name = node.name.text
        let parameters = node.signature.parameterClause.parameters.map(makeParameter(from:))
        let returnTypeText = node.signature.returnClause?.type.trimmedDescription
        let effects = node.signature.effectSpecifiers
        let isThrows = effects?.throwsClause != nil
        let isAsync = effects?.asyncSpecifier != nil
        let modifiers = node.modifiers.map { $0.name.text }
        let isMutating = modifiers.contains("mutating")
        let isStatic = modifiers.contains("static") || modifiers.contains("class")

        let position = node.funcKeyword.positionAfterSkippingLeadingTrivia
        let sourceLocation = converter.location(for: position)
        let location = SourceLocation(
            file: file,
            line: sourceLocation.line,
            column: sourceLocation.column
        )

        let containingTypeName = typeStack.last
        let bodySignals = scanBody(of: node)
        let discoverableGroup = AttributeScanner.discoverableGroup(in: node.attributes)
        let invariantKeypath = AttributeScanner.invariantKeypath(in: node.attributes)

        return FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnTypeText,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: isMutating,
            isStatic: isStatic,
            location: location,
            containingTypeName: containingTypeName,
            bodySignals: bodySignals,
            discoverableGroup: discoverableGroup,
            invariantKeypath: invariantKeypath
        )
    }

    private func makeParameter(from syntax: FunctionParameterSyntax) -> Parameter {
        // Swift parameter shapes:
        //   `func f(a: Int)`       → firstName=a, secondName=nil → label=a, name=a
        //   `func f(_ a: Int)`     → firstName=_, secondName=a   → label=nil, name=a
        //   `func f(label a: Int)` → firstName=label, secondName=a → label=label, name=a
        let firstName = syntax.firstName.text
        let secondName = syntax.secondName?.text

        let label: String?
        let internalName: String
        if let secondName {
            label = (firstName == "_") ? nil : firstName
            internalName = secondName
        } else {
            label = firstName
            internalName = firstName
        }

        let rawType = syntax.type.trimmedDescription
        let isInout = rawType.hasPrefix("inout ")
        let typeText = isInout ? String(rawType.dropFirst("inout ".count)) : rawType

        return Parameter(
            label: label,
            internalName: internalName,
            typeText: typeText,
            isInout: isInout
        )
    }

    private func scanBody(of node: FunctionDeclSyntax) -> BodySignals {
        guard let body = node.body else {
            return .empty
        }
        let scanner = BodySignalVisitor(funcName: node.name.text)
        scanner.walk(body)
        return BodySignals(
            hasNonDeterministicCall: !scanner.detectedAPIs.isEmpty,
            hasSelfComposition: scanner.foundSelfComposition,
            nonDeterministicAPIsDetected: scanner.detectedAPIs.sorted(),
            reducerOpsReferenced: scanner.reducerOps.sorted(),
            reducerOpsWithIdentitySeed: scanner.reducerOpsWithIdentitySeed.sorted()
        )
    }
}
