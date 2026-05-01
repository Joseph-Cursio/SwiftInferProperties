import SwiftDiagnostics

/// Diagnostics emitted by `@CheckProperty` expansion. Each case
/// renders a clear message plus a stable diagnostic ID so editor
/// integrations can group / suppress them per-rule.
enum SwiftInferMacroDiagnostic: String, DiagnosticMessage {
    case notAFunctionDecl
    case unrecognizedKind
    case idempotentRequiresUnaryShape
    case idempotentRequiresMatchingTypes
    case roundTripRequiresUnaryShape
    case roundTripRequiresDistinctTypes

    var severity: DiagnosticSeverity { .error }

    var diagnosticID: MessageID {
        MessageID(domain: "SwiftInferMacro", id: rawValue)
    }

    var message: String {
        switch self {
        case .notAFunctionDecl:
            return "@CheckProperty can only attach to a function declaration."
        case .unrecognizedKind:
            return "@CheckProperty's first argument must be `.idempotent` "
                + "or `.roundTrip(pairedWith:)`."
        case .idempotentRequiresUnaryShape:
            return "@CheckProperty(.idempotent) requires `func name(_: T) -> T` — "
                + "exactly one parameter and a non-nil return type."
        case .idempotentRequiresMatchingTypes:
            return "@CheckProperty(.idempotent) requires the parameter type and "
                + "return type to be identical (the `T -> T` shape)."
        case .roundTripRequiresUnaryShape:
            return "@CheckProperty(.roundTrip, pairedWith:) requires "
                + "`func name(_: T) -> U` — exactly one parameter and a non-nil "
                + "return type."
        case .roundTripRequiresDistinctTypes:
            return "@CheckProperty(.roundTrip, pairedWith:) requires the parameter "
                + "type and return type to differ. For T -> T use "
                + "@CheckProperty(.idempotent)."
        }
    }
}
