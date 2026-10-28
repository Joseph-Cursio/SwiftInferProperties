// @subject SwiftUMLStudio
// @revision 111d8bd
// @producer SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/String+Extensions.swift:48 String.globPatternToRegex()
// @call-site SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/String+Extensions.swift:58 isMatching(searchPattern:)
// @argument pattern, bound by `let pattern = searchPattern.globPatternToRegex()`
// @acceptor Regex(_:), untyped (control PC7 only; the real call site uses NSRegularExpression)
// @shims none; the producer is verbatim, and `internal extension String` is kept
import Foundation

internal extension String {
    /// Translate this glob pattern into an anchored regular-expression string
    /// (`^…$`): escape regex metacharacters, then expand `?`, `**/`, `**`, and `*`.
    func globPatternToRegex() -> String {
        "^\(self)$"
            .replacingOccurrences(of: "[.+(){\\\\|]", with: "\\\\$0", options: .regularExpression)
            .replacingOccurrences(of: "?", with: "[^/]")
            .replacingOccurrences(of: "**/", with: "(.+/)?")
            .replacingOccurrences(of: "**", with: ".+")
            .replacingOccurrences(of: "*", with: "([^/]+)?")
    }
}

func produce(_ input: String) -> String? { input.globPatternToRegex() }

func accepts(_ pattern: String) -> Bool { (try? Regex(pattern)) != nil }
