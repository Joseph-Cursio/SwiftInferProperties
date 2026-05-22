import SwiftInferCore

extension IdentityElementTemplate {

    // MARK: - Display helpers

    static func displayName(for summary: FunctionSummary) -> String {
        let labels = summary.parameters.map { ($0.label ?? "_") + ":" }.joined()
        return "\(summary.name)(\(labels))"
    }

    static func signature(for summary: FunctionSummary) -> String {
        let paramTypes = summary.parameters.map(\.typeText).joined(separator: ", ")
        var sig = "(\(paramTypes))"
        if summary.isAsync {
            sig += " async"
        }
        if summary.isThrows {
            sig += " throws"
        }
        sig += " -> \(summary.returnTypeText ?? "Void")"
        return sig
    }
}
