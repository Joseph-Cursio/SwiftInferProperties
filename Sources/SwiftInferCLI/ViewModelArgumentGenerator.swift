import Foundation

/// PROTOTYPE — deterministic, dependency-free candidate values for a
/// view-model action's single parameter, used by the idempotence verifier
/// (x-curried idempotence applies the action twice with the *same* value;
/// the property must hold for every candidate). Returns `nil` for a type
/// outside the curated set — the caller gates the action out of verify
/// (the MVVM analog of the `.tca` constructible-action subset).
///
/// **Why literals, not the strategist.** The no-arg verifier is a minimal
/// dependency-free SwiftPM package; keeping argument generation to literal
/// values preserves that (no `swift-property-based` runtime). A production
/// version would delegate to `DerivationStrategist` for proper randomized
/// generation + shrinking — the same posture as the algebraic verify path
/// (PRD §11). The curated set covers the common idempotence-witness
/// payloads (`Bool`/`Int`/`String`/`UUID`, plus their Optionals).
public enum ViewModelArgumentGenerator {

    /// A Swift expression of type `[<type>]` enumerating candidate values
    /// to apply the action with, or `nil` if `type` isn't generatable.
    public static func candidateValuesExpression(for type: String) -> String? {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("?") {
            let wrapped = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
            guard let inner = baseValues(for: wrapped) else { return nil }
            // `[<T>?] = [nil, v1, v2]` — nil plus each base value.
            return "[nil, " + inner.joined(separator: ", ") + "] as [\(trimmed)]"
        }
        guard let values = baseValues(for: trimmed) else { return nil }
        return "[" + values.joined(separator: ", ") + "]"
    }

    /// Whether a single-parameter type is generatable.
    public static func isGeneratable(_ type: String) -> Bool {
        candidateValuesExpression(for: type) != nil
    }

    /// Literal candidate values for a non-Optional curated type.
    private static func baseValues(for type: String) -> [String]? {
        switch type {
        case "Bool":
            return ["true", "false"]

        case "Int":
            return ["0", "1", "-1"]

        case "String":
            return ["\"\"", "\"x\""]

        case "UUID":
            // Fixed UUIDs (deterministic — `UUID()` would be random).
            return [
                "UUID(uuidString: \"00000000-0000-0000-0000-000000000000\")!",
                "UUID(uuidString: \"11111111-1111-1111-1111-111111111111\")!"
            ]

        default:
            return nil
        }
    }
}
