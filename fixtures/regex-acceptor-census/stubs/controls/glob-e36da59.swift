// @subject SwiftUMLStudio
// @revision e36da59
// @producer SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/String+Extensions.swift:77 String.globPatternToRegex()
// @call-site SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/String+Extensions.swift:99 isMatching(searchPattern:)
// @argument pattern, bound by `let pattern = searchPattern.globPatternToRegex()`
// @acceptor NSRegularExpression(pattern:options: [])
// @shims none; the producer is verbatim (doc comment dropped), and `internal extension String` is kept
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
