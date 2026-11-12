import Foundation

/// `ActivityGraphBuilder.compactText(_:)` at SwiftUMLStudio `e36da59`, the mutation run's revision, verbatim.
public enum CompactTextE36da59 {
    public static func compactText(_ text: String) -> String {
        let stripped = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let collapsed = stripped
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count > 80 { // THRESHOLD
            return String(collapsed.prefix(77)) + "…"
        }
        return collapsed
    }
}
