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
    ///
    /// **Public because the eighth copy lived in another module and was the one that went
    /// wrong.** `Discover+GenericLaws` could not see this property, so it rebuilt the row by
    /// hand — display name, signature and location, and nothing else. Every determinism law
    /// therefore reached the stub emitter with no declaring type, no receiver and no isolation,
    /// and not one determinism stub for a type member compiled across the corpus funnel census:
    /// **33 of 33 that built were free functions** (#465).
    public var inferenceEvidence: Evidence {
        Evidence(
            displayName: inferenceDisplayName,
            signature: inferenceSignature,
            location: location,
            isInstanceMethod: containingTypeName != nil && !isStatic,
            isMutatingMethod: isMutating,
            isNullary: parameters.isEmpty,
            returnsSelfType: inferenceReturnsSelfType,
            isComputedProperty: isComputedProperty,
            parameterTypeNames: parameters.map(\.typeText),
            parameterInternalNames: parameters.map(\.internalName),
            qualifiedTypeName: qualifiedContainingTypeName,
            globalActor: globalActor,
            declaresNonisolated: declaresNonisolated,
            genericParameters: genericParameters,
            inoutParameterIndices: parameters.indices.filter { parameters[$0].isInout }
        )
    }

    /// True when the return type names the carrier itself: `Self`, or the
    /// containing type compared up to generic arguments (so
    /// `func sorted() -> OrderedSet<Element>` on `OrderedSet` counts).
    private var inferenceReturnsSelfType: Bool {
        guard let returnTypeText else { return false }
        if returnTypeText == "Self" { return true }
        guard let containingTypeName else { return false }
        func baseName(_ text: String) -> Substring {
            text.prefix { $0 != "<" }
        }
        return baseName(returnTypeText) == baseName(containingTypeName)
    }
}
