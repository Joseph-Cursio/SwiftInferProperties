import SwiftDiagnostics

/// Diagnostics emitted by `@CheckProperty` expansion. Each case
/// renders a clear message plus a stable diagnostic ID so editor
/// integrations can group / suppress them per-rule.
enum SwiftInferMacroDiagnostic: String, DiagnosticMessage {
    case notAFunctionDecl
    case unrecognizedKind
    case roundTripNotYetShipped
    case idempotentRequiresUnaryShape
    case idempotentRequiresMatchingTypes

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
        case .roundTripNotYetShipped:
            return "@CheckProperty(.roundTrip, pairedWith:) lands in M5.3. "
                + "M5.2 ships only the .idempotent arm."
        case .idempotentRequiresUnaryShape:
            return "@CheckProperty(.idempotent) requires `func name(_: T) -> T` — "
                + "exactly one parameter and a non-nil return type."
        case .idempotentRequiresMatchingTypes:
            return "@CheckProperty(.idempotent) requires the parameter type and "
                + "return type to be identical (the `T -> T` shape)."
        }
    }
}
