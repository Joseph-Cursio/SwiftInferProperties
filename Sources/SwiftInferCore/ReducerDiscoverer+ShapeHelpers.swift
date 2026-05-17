import Foundation
import SwiftSyntax

/// V1.92 lint pass — shape-classification + scalar-filter helpers
/// extracted from `ReducerDiscoverer.swift` so the main file stays
/// under SwiftLint's 400-line cap. V1.93 added the
/// `hasReducerAttribute` helper for the M1.D macro path. All
/// helpers are static-internal (callable from the Visitor in the
/// main file); none depend on per-Visitor state, so they're
/// naturally pure.
extension ReducerDiscoverer {

    /// V1.93 (cycle-90 fix for cycle-87 finding #3) — does an attribute
    /// list contain `@Reducer`? Matches the canonical macro name
    /// with or without parameter clause (`@Reducer` or
    /// `@Reducer(state: .equatable)`) — both have the same
    /// `attributeName.trimmedDescription`. Modern TCA (1.0+) attaches
    /// `Reducer` conformance via this macro rather than the explicit
    /// `: Reducer` inheritance clause; cycle-87 measured every TCA
    /// 1.25.5 example as 0 detections because v1.92's M1.B walker
    /// only recognized the conformance clause.
    static func hasReducerAttribute(_ attributes: AttributeListSyntax) -> Bool {
        for element in attributes {
            guard let attribute = element.as(AttributeSyntax.self) else { continue }
            let name = attribute.attributeName.trimmedDescription
            if name == "Reducer" {
                return true
            }
        }
        return false
    }

    /// V1.92 (cycle-89 fix for cycle-87 finding #4) — does `returnType`
    /// look like `Effect<...>`? Matches the canonical TCA effect
    /// shape; doesn't validate the type argument since M1.B's
    /// closure walker also leaves it unchecked (mirror the existing
    /// posture). Accepts both `Effect<Action>` and namespaced
    /// `Effect<Module.Action>`.
    static func looksLikeEffect(_ returnType: String) -> Bool {
        returnType.hasPrefix("Effect<") && returnType.hasSuffix(">")
    }

    /// Does `returnType` look like `(<expectedFirst>, Effect<...>)`?
    /// Tuple-shape match by depth-counting comma split — handles
    /// generic args like `Effect<Action>` and `Effect<S.Action>`
    /// without choking on nested `<>` / `()` / `[]`.
    static func isStateEffectTuple(_ returnType: String, expectedFirst: String) -> Bool {
        guard returnType.hasPrefix("(") && returnType.hasSuffix(")") else { return false }
        let inner = returnType.dropFirst().dropLast()
        var depth = 0
        var commaIdx: String.Index?
        for index in inner.indices {
            let char = inner[index]
            switch char {
            case "<", "(", "[": depth += 1
            case ">", ")", "]": depth -= 1
            case ",":
                if depth == 0 {
                    commaIdx = index
                }
            default:
                break
            }
            if commaIdx != nil { break }
        }
        guard let commaIdx else { return false }
        let firstHalf = inner[..<commaIdx].trimmingCharacters(in: .whitespaces)
        let secondHalf = inner[inner.index(after: commaIdx)...]
            .trimmingCharacters(in: .whitespaces)
        return firstHalf == expectedFirst && secondHalf.hasPrefix("Effect")
    }

    /// V1.92 (cycle-89 fix for cycle-87 finding #1) — curated scalar
    /// type set. Two-scalar reducer shapes (both State and Action
    /// in this set) are rejected as false positives — no plausible
    /// reducer has both halves scalar. Set covers Swift's stdlib
    /// numeric tower + Bool / String / Character; excludes
    /// `Optional<X>` (which is `X?` syntactically) and collection
    /// types like `[T]` since those occasionally legitimately
    /// stand in for compact State.
    static func isScalarTypeName(_ typeName: String) -> Bool {
        scalarTypeNames.contains(typeName)
    }

    private static let scalarTypeNames: Set<String> = [
        "Int", "UInt",
        "Int8", "Int16", "Int32", "Int64",
        "UInt8", "UInt16", "UInt32", "UInt64",
        "Bool",
        "Double", "Float", "Float80",
        "String", "Character",
        "Swift.Int", "Swift.UInt",
        "Swift.Int8", "Swift.Int16", "Swift.Int32", "Swift.Int64",
        "Swift.UInt8", "Swift.UInt16", "Swift.UInt32", "Swift.UInt64",
        "Swift.Bool",
        "Swift.Double", "Swift.Float",
        "Swift.String", "Swift.Character"
    ]
}
