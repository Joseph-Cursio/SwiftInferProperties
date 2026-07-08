import Foundation

/// V1.146 — best-effort detection of which standard-library types a target's
/// source uses, to scope `known-properties --target` to the laws that are
/// actually relevant. A heuristic (word-token match + array-type syntax),
/// not a full type check — a slight *superset* is the right failure mode for
/// a convenience filter, so it errs toward showing a type rather than hiding
/// a used one.
enum StdlibTypeUsage {

    /// Which of `candidates` appears in `sources`. `Array` also matches the
    /// `[Type]` collection-type syntax (arrays are rarely written `Array<T>`);
    /// the others match their name as a word token.
    static func typesUsed(in sources: [String], among candidates: Set<String>) -> Set<String> {
        let joined = sources.joined(separator: "\n")
        var found: Set<String> = []
        for type in candidates where isUsed(type, in: joined) {
            found.insert(type)
        }
        return found
    }

    private static func isUsed(_ type: String, in source: String) -> Bool {
        if matches(#"\b\#(type)\b"#, in: source) { return true }
        // Arrays are usually `[T]` / `[1, 2]`, not `Array<T>`: accept an
        // array-TYPE bracket group (a capitalized element, no `:` so it isn't
        // a dictionary) or a non-empty array literal.
        if type == "Array" {
            // `[Type]` annotation (capitalized element, no `:`), or a
            // comma-separated literal with no `:` (an array, not a dictionary).
            return matches(#"\[\s*[A-Z][A-Za-z0-9_.<>?]*\s*\]"#, in: source)
                || matches(#"\[[^:\]\n]*,[^:\]\n]*\]"#, in: source)
        }
        return false
    }

    private static func matches(_ pattern: String, in source: String) -> Bool {
        source.range(of: pattern, options: .regularExpression) != nil
    }
}
