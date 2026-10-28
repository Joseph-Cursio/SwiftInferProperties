// @producer-id SwiftUMLStudio:SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/String+Extensions.swift:4968
// @rows SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/String+Extensions.swift:125
// @subject SwiftUMLStudio b8b1520, the local checkout on 2026-10-27 (origin/main was c6c82e3, 299 commits on)
// @producer String+Extensions.swift:102 String.globPatternToRegex(), verbatim (doc comment dropped)
// @argument `pattern`, bound by `let pattern = searchPattern.globPatternToRegex()` (isMatching), inlined
// @drives the receiver
// @shims none; `internal extension String` kept
import Foundation

internal extension String {
    func globPatternToRegex() -> String {
        let escaped = replacingOccurrences(
            of: "[.+(){}^$\\\\|]",
            with: "\\\\$0",
            options: .regularExpression
        )
        return "^\(escaped)$"
            .replacingOccurrences(of: "?", with: "[^/]")
            .replacingOccurrences(of: "**/", with: "(.+/)?")
            .replacingOccurrences(of: "**", with: ".+")
            .replacingOccurrences(of: "*", with: "([^/]+)?")
    }
}

func produce(_ input: String) -> String? { input.globPatternToRegex() }

func accepts(_ pattern: String) -> Bool { (try? NSRegularExpression(pattern: pattern, options: [])) != nil }
