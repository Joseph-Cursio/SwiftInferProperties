import SwiftInferCore

extension FunctionSummary {
    /// Human-facing call shape with parameter labels, e.g. `normalize(_:)`.
    ///
    /// Used to build the `displayName` of an `Evidence` row.
    var inferenceDisplayName: String {
        let labels = parameters.map { ($0.label ?? "_") + ":" }.joined()
        return "\(name)(\(labels))"
    }

    /// Rendered type signature, e.g. `(String) async throws -> String`.
    ///
    /// Used to build the `signature` of an `Evidence` row. (The invariant-
    /// preservation template appends a ` preserving <keyPath>` suffix and so
    /// keeps its own variant.)
    var inferenceSignature: String {
        let paramTypes = parameters.map(\.typeText).joined(separator: ", ")
        var sig = "(\(paramTypes))"
        if isAsync {
            sig += " async"
        }
        if isThrows {
            sig += " throws"
        }
        sig += " -> \(returnTypeText ?? "Void")"
        return sig
    }

    /// Evidence row for this function: display name + signature + location.
    ///
    /// Previously copy-pasted as `makeEvidence(_:)` / `displayName(for:)` /
    /// `signature(for:)` across seven-plus templates.
    var inferenceEvidence: Evidence {
        Evidence(
            displayName: inferenceDisplayName,
            signature: inferenceSignature,
            location: location
        )
    }
}
