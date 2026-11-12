import Foundation

/// `ActivityGraphBuilder.compactText(_:)` at SwiftUMLStudio `9ad7631` (HEAD on 2026-11-11), verbatim.
public enum CompactText9ad7631 {
    public static func compactText(_ text: String) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count > 80 { // THRESHOLD
            return String(collapsed.prefix(77)) + "…"
        }
        return collapsed
    }
}
