// @producer-id SwiftUMLStudio:SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Parsing/Glob.swift:6491
// @rows SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Parsing/Glob.swift:176
// @subject SwiftUMLStudio b8b1520, the local checkout on 2026-10-27 (origin/main was c6c82e3, 299 commits on)
// @producer Glob.swift:136 globRegexPattern(anchor:pattern:tokens:), verbatim (doc comment dropped), with its
//           helper String.globPatternToRegex() (String+Extensions.swift:102) verbatim
// @argument `regex`, bound by `let regex = globRegexPattern(anchor: anchor, pattern: pattern, tokens: tokens)`
//           (expandGlobs, Glob.swift:174), inlined
// @drives `pattern`; representatives: `anchor` = "/repo/Sources" (a canonical directory, as splitGlobEntry returns), `tokens` = [:]. At the call site `anchor`, `pattern` and `tokens` are
//           not literals: splitGlobEntry's results and expandGlobs' brace alternations
// @shims none
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

internal func globRegexPattern(anchor: String, pattern: String, tokens: [String: String] = [:]) -> String {
    guard !pattern.isEmpty else {
        return "^\(NSRegularExpression.escapedPattern(for: anchor))$"
    }
    var patternRegex = String(pattern.globPatternToRegex().dropFirst())
    for (token, replacement) in tokens {
        patternRegex = patternRegex.replacingOccurrences(of: token, with: replacement)
    }
    let directory = anchor.hasSuffix("/") ? anchor : anchor + "/"
    return "^" + NSRegularExpression.escapedPattern(for: directory) + patternRegex
}

func produce(_ input: String) -> String? { globRegexPattern(anchor: "/repo/Sources", pattern: input, tokens: [:]) }

func accepts(_ pattern: String) -> Bool { (try? NSRegularExpression(pattern: pattern, options: [])) != nil }
