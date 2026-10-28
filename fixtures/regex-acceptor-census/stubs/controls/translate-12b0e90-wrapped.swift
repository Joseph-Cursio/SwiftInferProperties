// @subject SwiftAssist
// @revision 12b0e90
// @producer Sources/SwiftAssist/Agent/Tools/FilesystemTools.swift:296 GlobTool.translate(glob:)
// @call-site Sources/SwiftAssist/Agent/Tools/FilesystemTools.swift:244 GlobTool.execute(call:context:)
// @argument `"^" + translated + "$"`, with `let translated = Self.translate(glob: pattern)`
// @acceptor NSRegularExpression(pattern:), default options
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
