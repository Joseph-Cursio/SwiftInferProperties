// @producer-id SwiftAssist:Sources/SwiftAssist/Agent/Tools/FilesystemTools.swift:12936
// @rows Sources/SwiftAssist/Agent/Tools/FilesystemTools.swift:244
// @subject SwiftAssist 6974842 (HEAD on 2026-10-27; this file is unchanged since 12b0e90)
// @producer FilesystemTools.swift:296 GlobTool.translate(glob:), verbatim
// @argument `"^" + translated + "$"`, with `let translated = Self.translate(glob: pattern)`, inlined
// @drives `glob`
// @shims `GlobTool` is a public struct conforming to AgentTool with other members; an empty
//        `enum GlobTool` stands in for it, and the static method is verbatim
import Foundation

enum GlobTool {
    /// Translates a simple glob (`*`, `**`, `?`, `[...]`) into a regex.
    static func translate(glob: String) -> String {
        var result = ""
        var index = glob.startIndex
        while index < glob.endIndex {
            let char = glob[index]
            switch char {
            case "*":
                let next = glob.index(after: index)
                if next < glob.endIndex, glob[next] == "*" {
                    result += ".*"
                    index = glob.index(after: next)
                    continue
                }
                result += "[^/]*"

            case "?":
                result += "[^/]"

            case ".", "(", ")", "+", "|", "^", "$", "{", "}", "\\":
                result += "\\\(char)"

            default:
                result.append(char)
            }
            index = glob.index(after: index)
        }
        return result
    }
}

func produce(_ input: String) -> String? { "^" + GlobTool.translate(glob: input) + "$" }

func accepts(_ pattern: String) -> Bool { (try? NSRegularExpression(pattern: pattern)) != nil }
