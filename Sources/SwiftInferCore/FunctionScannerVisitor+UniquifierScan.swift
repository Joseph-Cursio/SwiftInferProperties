import SwiftSyntax

extension FunctionScannerVisitor {
    /// A non-static method of a type, or a function with an `inout` parameter: where a uniquifier's state
    /// can live across calls. The owner's kind (class, actor or value type) is read by the template.
    func keepsState(_ node: FunctionDeclSyntax) -> Bool {
        let modifiers = node.modifiers.map(\.name.text)
        let isStatic = modifiers.contains("static") || modifiers.contains("class")
        let hasInout = node.signature.parameterClause.parameters.contains {
            $0.type.trimmedDescription.hasPrefix("inout ")
        }
        return hasInout || (!typeStack.isEmpty && !isStatic)
    }

    /// The stored state a non-static method writes and removes from, or `nil` when it touches none, so
    /// every other summary's signals stay what they were before the uniquifier template read them.
    func recordedStateWrites(_ node: FunctionDeclSyntax) -> StateWrites? {
        guard keepsState(node) else { return nil }
        let writes = UniquifierShapeReader.stateWrites(of: node)
        return writes == .empty ? nil : writes
    }

    /// The result is not empty, `Void`, `()` or `Never` (#669's RETURNS).
    static func returnsValue(_ node: FunctionDeclSyntax) -> Bool {
        guard let result = node.signature.returnClause?.type.trimmedDescription else { return false }
        return !["Void", "()", "Never"].contains(result)
    }
}
