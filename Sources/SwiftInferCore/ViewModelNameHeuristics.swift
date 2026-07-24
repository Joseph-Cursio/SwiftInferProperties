/// Textual field- and name-shape heuristics shared by the two prototype MVVM
/// carriers — the CLI-side `ViewModelInvariantResolvers` and the Templates-side
/// `ViewModelInteractionAnalyzer` — which had each carried a byte-identical
/// private copy of these helpers (including the presentation-name and
/// boolean-prefix lists the drift rule flagged).
///
/// Pure string heuristics with no type resolution, matching the prototypes'
/// textual model: they read a type annotation or property name exactly as
/// written. Both carriers are prototypes; if that lift is dropped, this goes
/// with them.
public enum ViewModelNameHeuristics {

    /// A textual `Optional` — the annotation ends in `?`.
    public static func isOptional(_ type: String) -> Bool {
        type.hasSuffix("?")
    }

    /// Strip trailing optional markers (`?` / `!`) and surrounding whitespace:
    /// `"Foo? "` → `"Foo"`.
    public static func stripOptional(_ type: String) -> String {
        var trimmed = type.trimmingCharacters(in: .whitespaces)
        while trimmed.hasSuffix("?") || trimmed.hasSuffix("!") {
            trimmed = String(trimmed.dropLast())
        }
        return trimmed.trimmingCharacters(in: .whitespaces)
    }

    /// A `Bool` field, optional or not.
    public static func isBool(_ type: String) -> Bool {
        stripOptional(type) == "Bool"
    }

    /// A collection-shaped field: array literal, `Set` / `Array` / `Dictionary`
    /// generic, or `IdentifiedArray`.
    public static func isCollection(_ type: String) -> Bool {
        let base = stripOptional(type)
        return base.hasPrefix("[")
            || base.contains("Set<") || base.contains("Array<")
            || base.contains("Dictionary<") || base.contains("IdentifiedArray")
    }

    /// A name that reads like a presentation route (`sheet`, `alert`, …) —
    /// substring match, case-insensitive.
    public static func isPresentationName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return ["sheet", "alert", "popover", "route", "destination", "presented", "cover", "dialog"]
            .contains { lowered.contains($0) }
    }

    /// Strip a Bool's `is` / `has` / `show` / `should` / … prefix to its stem
    /// (`isLoading` → `loading`), lowercased; the whole name lowercased if no
    /// prefix strips.
    public static func booleanStem(_ name: String) -> String {
        let lowered = name.lowercased()
        for prefix in ["isshowing", "is", "has", "show", "should", "did", "will"]
        where lowered.hasPrefix(prefix) && lowered.count > prefix.count {
            return String(lowered.dropFirst(prefix.count))
        }
        return lowered
    }
}
