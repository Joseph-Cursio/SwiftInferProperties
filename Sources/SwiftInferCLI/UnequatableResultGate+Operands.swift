import Foundation

/// Which type names a comparison of two results with `==` actually needs `Equatable` for.
///
/// Split out of `UnequatableResultGate.swift` so the reading of a type spelling sits apart from the
/// reading of conformances. The gate used to judge EVERY identifier in a result spelling, so
/// `KeyPath<Row, String>` declined on `Row` — a stub that compiled, withdrawn.
extension UnequatableResultGate {

    /// The standard-library generics whose `==` exists exactly when their arguments' does, so a
    /// comparison of one compares its arguments too. Any other generic is judged by its own name.
    static let argumentComparingGenerics: Set<String> = [
        "Optional", "Array", "ContiguousArray", "ArraySlice", "Set", "Dictionary", "Result"
    ]

    /// The type names whose own `==` comparing two values spelled `spelling` needs, in order.
    ///
    /// Sugar and `argumentComparingGenerics` are looked through to their arguments — `[K: V]` to
    /// both, a tuple to each member with its label dropped. Any other generic gives its base name
    /// alone, so `KeyPath<Row, String>` gives `KeyPath` and `Row` is never asked about; a generic
    /// whose arguments do not close the spelling (`Outer<Int>.Inner`) gives the spelling whole,
    /// which names no scanned key. `some P` and `any P` give nothing: neither is a type to judge.
    static func operandTypeNames(in spelling: String) -> [String] {
        let type = spelling.trimmingCharacters(in: .whitespaces)
        if type.isEmpty || type.hasPrefix("some ") || type.hasPrefix("any ") { return [] }
        if type.hasSuffix("?") || type.hasSuffix("!") {
            return operandTypeNames(in: String(type.dropLast()))
        }
        if let inner = enclosedContents(of: type, opening: "[", closing: "]") {
            return topLevelParts(of: inner, separatedBy: ":").flatMap { operandTypeNames(in: $0) }
        }
        if let inner = enclosedContents(of: type, opening: "(", closing: ")") {
            return topLevelParts(of: inner, separatedBy: ",").flatMap { operandTypeNames(in: droppingLabel($0)) }
        }
        guard let open = type.firstIndex(of: "<"),
              let arguments = enclosedContents(of: String(type[open...]), opening: "<", closing: ">")
        else { return [type] }
        let base = String(type[..<open])
        let unqualified = base.hasPrefix("Swift.") ? String(base.dropFirst("Swift.".count)) : base
        guard argumentComparingGenerics.contains(unqualified) else { return [base] }
        return topLevelParts(of: arguments, separatedBy: ",").flatMap { operandTypeNames(in: $0) }
    }

    /// The text inside `text`'s first character, when that is `opening` and the bracket closing it
    /// is `text`'s last character: `[A]` gives `A`; `[A].Type` and `(A) -> B` give `nil`.
    private static func enclosedContents(of text: String, opening: Character, closing: Character) -> String? {
        guard text.count >= 2, text.first == opening, text.last == closing else { return nil }
        var depth = 0
        var previous: Character = " "
        for (offset, character) in text.enumerated() {
            depth += depthChange(character, after: previous)
            previous = character
            if depth == 0 {
                return offset == text.count - 1 ? String(text.dropFirst().dropLast()) : nil
            }
        }
        return nil
    }

    /// `text` split at each `separator` outside every bracket.
    private static func topLevelParts(of text: String, separatedBy separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var previous: Character = " "
        for character in text {
            if character == separator, depth == 0 {
                parts.append(current)
                current = ""
            } else {
                depth += depthChange(character, after: previous)
                current.append(character)
            }
            previous = character
        }
        parts.append(current)
        return parts
    }

    /// A tuple member without its label: `text: String` gives `String`.
    private static func droppingLabel(_ member: String) -> String {
        let parts = topLevelParts(of: member, separatedBy: ":")
        guard parts.count == 2,
              parts[0].trimmingCharacters(in: .whitespaces).wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*/) != nil
        else { return member }
        return parts[1]
    }

    /// How a character moves bracket depth. The `>` of an arrow, `->`, closes nothing.
    private static func depthChange(_ character: Character, after previous: Character) -> Int {
        switch character {
        case "[", "(", "<":
            return 1

        case "]", ")":
            return -1

        case ">":
            return previous == "-" ? 0 : -1

        default:
            return 0
        }
    }
}
