import Foundation
import SwiftInferCore

/// Resolving a bare type name to the type it names in the function's own scope, before pairing.
///
/// **The same pathology as `Self`, through a different spelling.** `resolvingSelf` exists because
/// every `(Self) -> Self` method read as the inverse of every other. A nested type's bare name does
/// the same across types: OpenAPIKit declares a `CodingKeys` inside each of dozens of types, each with
/// `var stringValue: String` and `static func extendedKey(for: String) -> CodingKeys`, so
/// `Document.CodingKeys.stringValue` read as the inverse of `Operation.CodingKeys.extendedKey(for:)` —
/// **1,520 of 2,372 round-trip rows**, every one a false pairing of two unrelated types
/// (`docs/measurements/round-trip-pairing-evidence.md`).
///
/// The rule is Swift's own lookup: from the function's qualified containing type outward, the first
/// `<scope>.<Name>` that the scanned summaries declare. A name that resolves nowhere stays as written,
/// on both sides alike, so nothing that paired correctly stops pairing — two functions of one type
/// resolve a name the same way, and a real inverse between two types already differs in type text.
extension FunctionPairing {

    /// A function's domain and codomain after resolution, computed once per function.
    struct ResolvedShape {
        let domain: String?
        let codomain: String?
    }

    /// Every type path the summaries declare a function inside, with each enclosing path —
    /// `OpenAPI.Document.CodingKeys` contributes itself, `OpenAPI.Document` and `OpenAPI`.
    static func declaredTypePaths(in summaries: [FunctionSummary]) -> Set<String> {
        var paths: Set<String> = []
        for path in summaries.compactMap(\.qualifiedContainingTypeName) {
            var components = path.split(separator: ".").map(String.init)
            while !components.isEmpty {
                paths.insert(components.joined(separator: "."))
                components.removeLast()
            }
        }
        return paths
    }

    /// `typeText` with `Self` resolved, then each bare type name — the head of any dotted spelling —
    /// replaced by the innermost declared `<scope>.<Name>` visible from the function's scope.
    static func resolvingScopedNames(
        _ typeText: String,
        declaredIn summary: FunctionSummary,
        declared: Set<String>
    ) -> String {
        let text = resolvingSelf(typeText, declaredIn: summary)
        guard let scope = summary.qualifiedContainingTypeName, !declared.isEmpty else { return text }
        let components = scope.split(separator: ".").map(String.init)
        var result = ""
        var identifier = ""
        var previous: Character = " "
        func flush() {
            defer { identifier = "" }
            guard !identifier.isEmpty else { return }
            guard previous != "." else {
                result += identifier
                return
            }
            for depth in stride(from: components.count, through: 1, by: -1) {
                let candidate = (components.prefix(depth) + [identifier]).joined(separator: ".")
                if declared.contains(candidate) {
                    result += candidate
                    return
                }
            }
            // The name may itself be a scope component: `Document` inside `OpenAPI.Document.CodingKeys`.
            if let index = components.lastIndex(of: identifier) {
                result += components.prefix(index + 1).joined(separator: ".")
                return
            }
            result += identifier
        }
        for character in text {
            if character.isLetter || character.isNumber || character == "_" {
                if identifier.isEmpty { previous = result.last ?? " " }
                identifier.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }
}
