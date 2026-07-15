import Foundation
import PropertyLawCore

/// Tuple-carrier generation. The kit's `composedGenerator` recurses through
/// `Array` / `Set` / `Dictionary` / `Optional` but NOT tuples (a probe found
/// `(Int, Int)` gating at `unsupported-carrier`), so a `swapTwice((Int, Int))`
/// or `ordered((Int, Int))` pick could never verify. This composes a tuple
/// generator from its component generators via the kit's free `zip` combinator
/// (PropertyBased, arities 2…9), resolving each component the same way a
/// top-level carrier is — a `RawType` scalar, a nested tuple, or
/// `composedGenerator` for an `Array` / `Set` / `Dictionary` / `Optional`
/// component over resolvable leaves.
extension StrategistDispatchEmitter {

    /// A tuple carrier `(A, B, …)` → `zip(genA, genB, …)`, or `nil` when the
    /// carrier isn't a tuple, has fewer than 2 / more than 9 components (the
    /// kit's `zip` overloads stop at 9), or any component can't be generated.
    static func tupleRecipe(
        carrier: String,
        resolve: DerivationStrategist.CustomTypeResolver
    ) -> GeneratorRecipe? {
        guard let components = tupleComponents(of: carrier),
              (2...9).contains(components.count) else {
            return nil
        }
        var expressions: [String] = []
        var imports: Set<String> = ["Foundation", "PropertyBased"]
        for component in components {
            guard let resolved = componentGenerator(for: component, resolve: resolve) else {
                return nil
            }
            expressions.append(resolved.expression)
            imports.formUnion(resolved.imports)
        }
        // Single-line — the stub embeds the expression in a `//` header comment,
        // so an embedded newline would uncomment the tail (matches the memberwise
        // recipe's single-line `zip(...).map { … }`).
        return GeneratorRecipe(
            expression: "zip(" + expressions.joined(separator: ", ") + ")",
            carrierTypeName: canonicalTupleName(components),
            imports: imports.sorted()
        )
    }

    /// Split a tuple type spelling into its top-level component types, or `nil`
    /// if it isn't a tuple. `(Int)` is parenthesized-`Int` (one component → not a
    /// tuple), `()` is `Void`, and a labelled component (`x: Int`) is unwrapped to
    /// its type.
    static func tupleComponents(of carrier: String) -> [String]? {
        let trimmed = carrier.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("("), trimmed.hasSuffix(")") else {
            return nil
        }
        let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty else {
            return nil
        }
        let parts = splitTopLevel(inner)
        guard parts.count >= 2 else {
            return nil
        }
        return parts.map(stripTupleLabel)
    }

    /// A component's generator expression + imports: a `RawType` scalar, a nested
    /// tuple, or the kit's `composedGenerator` (Array/Set/Dictionary/Optional over
    /// resolvable leaves). `nil` when the component can't be generated — that
    /// gates the whole tuple.
    private static func componentGenerator(
        for component: String,
        resolve: DerivationStrategist.CustomTypeResolver
    ) -> (expression: String, imports: Set<String>)? {
        if let rawType = RawType(typeName: component) {
            let imports: Set<String> = (component == "Double" || component == "Float")
                ? ["Foundation", "PropertyBased", "RealModule"]
                : ["Foundation", "PropertyBased"]
            return (rawType.generatorExpression, imports)
        }
        if let nested = tupleRecipe(carrier: component, resolve: resolve) {
            return (nested.expression, Set(nested.imports))
        }
        if let composed = DerivationStrategist.composedGenerator(forTypeName: component, resolve: resolve) {
            return (composed.expression, Set(["Foundation", "PropertyBased"]).union(composed.requiredImports))
        }
        return nil
    }

    /// Split on top-level commas — those at bracket depth 0, so a component that
    /// is itself a `Dictionary` (`[Int: String]`), array, tuple, or generic stays
    /// intact.
    private static func splitTopLevel(_ text: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for char in text {
            switch char {
            case "(", "[", "<":
                depth += 1
                current.append(char)

            case ")", "]", ">":
                depth -= 1
                current.append(char)

            case "," where depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""

            default:
                current.append(char)
            }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty {
            parts.append(last)
        }
        return parts
    }

    /// `"x: Int"` → `"Int"`. Strips a leading bare-identifier label before the
    /// first top-level colon; leaves a `Dictionary` component (`[Int: String]`,
    /// whose colon is bracketed) untouched.
    private static func stripTupleLabel(_ component: String) -> String {
        guard let colonIndex = topLevelColonIndex(in: component) else {
            return component
        }
        let label = component[..<colonIndex].trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty,
              label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return component
        }
        return String(component[component.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
    }

    /// The index of the first colon at bracket depth 0, or `nil`.
    private static func topLevelColonIndex(in text: String) -> String.Index? {
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            switch text[index] {
            case "(", "[", "<": depth += 1
            case ")", "]", ">": depth -= 1
            case ":" where depth == 0: return index
            default: break
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Canonical unlabelled tuple spelling for the generator's type annotation —
    /// `zip` produces an unlabelled tuple, so the `Generator<(Int, Int), …>`
    /// annotation must match.
    private static func canonicalTupleName(_ components: [String]) -> String {
        "(" + components.joined(separator: ", ") + ")"
    }
}
