import Foundation
import SwiftInferCore

/// The `// Access:` block a stub carries when no test can reach its subject, and the edit that
/// unblocks it.
extension InteractiveTriage {

    /// The access caveat block, or empty for a subject a test can reach.
    static func accessCaveat(for suggestion: Suggestion) -> String {
        guard let signal = suggestion.score.signals.first(where: { $0.kind == .subjectNotVisibleToTests })
        else { return "" }
        let edit = widenTarget(for: suggestion).map { "// \($0)\n" } ?? ""
        return "// Access: \(signal.detail)\n\(edit)// This file will not compile until that is done.\n"
    }

    /// The exact edit that unblocks a restricted subject — `Delete `private` at Foo.swift:42` —
    /// naming **every** keyword in the way, or `nil` when none is found.
    ///
    /// **All of them, because deleting one of several is the named trap.** A `private func` inside
    /// a `private class` needs both keywords gone; naming only the member's proposes a patch that
    /// compiles and changes nothing — `SpeculativeWidening`'s own doc calls that the design's named
    /// trap. The header used to read the declaration's line alone, so it named exactly that
    /// no-op, one line below a remedy saying it was one. And a member of a `private extension`
    /// carries no keyword of its own, so it named nothing, while the remedy pointed at an enclosing
    /// type that was already `public`. `RestrictedScopes` finds the keywords where they are.
    ///
    /// An extension's keyword sets the default for every member in it, so deleting it widens more
    /// than the subject — said in the edit, with the narrower alternative, rather than left for the
    /// reader to discover in review.
    static func widenTarget(for suggestion: Suggestion) -> String? {
        guard let location = suggestion.evidence.first?.location,
              location.line > 0,
              let source = try? String(contentsOfFile: location.file, encoding: .utf8) else {
            return nil
        }
        return widenTarget(
            fileName: URL(fileURLWithPath: location.file).lastPathComponent,
            line: location.line,
            source: source
        )
    }

    /// The edit sentence for the declaration at `line` of `source`, or `nil` when no keyword blocks it.
    static func widenTarget(fileName name: String, line: Int, source: String) -> String? {
        let scopes = RestrictedScopes.blocking(declarationAt: line, in: source)
        guard !scopes.isEmpty else { return nil }
        if scopes.count == 1, scopes[0].enclosing == nil {
            return "Delete `\(scopes[0].modifier)` at \(name):\(scopes[0].line), or lift the logic out."
        }
        let edits = scopes.map { scope in
            "`\(scope.modifier)` at \(name):\(scope.line) (\(scope.enclosing.map { "`\($0)`" } ?? "the declaration"))"
        }
        var sentence = "Delete " + edits.joined(separator: " and ") + ", or lift the logic out."
        if let widening = scopes.first(where: \.widensSiblings), let label = widening.enclosing {
            sentence += " Deleting it from `\(label)` widens every member of that extension;"
                + " moving this declaration into an unmarked extension widens only it."
        }
        return sentence
    }
}
