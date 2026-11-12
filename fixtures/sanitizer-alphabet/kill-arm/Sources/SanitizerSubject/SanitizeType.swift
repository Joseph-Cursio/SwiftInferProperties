// Copied verbatim from SwiftUMLStudio `9ad7631` (the body is identical at `e36da59`, lines 169–179) for #672's kill
// arm (`docs/plans/sanitizer-alphabet-census-scope.md` §1.1): `ERScript.sanitizeType` from
// `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/ERScript.swift`. The `// L17x` comments are the
// mutation anchors (as-run line numbers); nothing else is changed.
import Foundation

public enum ERScript {
    /// Mermaid type tokens may not contain whitespace, brackets, or angle
    /// brackets. Collapse any such characters to underscores so the parser
    /// accepts the output.
    static func sanitizeType(_ raw: String) -> String {
        var sanitized = ""
        for scalar in raw.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" { // L172
                sanitized.unicodeScalars.append(scalar) // L173
            } else {
                sanitized += "_"
            }
        }
        return sanitized.isEmpty ? "Unknown" : sanitized // L178
    }
}
