/// Rewriting a `guard-domain` condition and its returned expression so they can be **evaluated
/// from a test** rather than from inside the declaration they were read out of (#468).
///
/// ## The problem, stated precisely
///
/// `guard-domain` is the one template whose law is **source text the tool did not write**.
/// `GuardDomain` carries `condition: "scale > 0"` and `returnedExpression: "0"` exactly as they
/// appear in the body, and those names mean what they mean *inside* `wordCount(forScale scale:)`.
/// A stub has different names for the same values: a drawn `value`, or `args.1`, and a receiver it
/// constructed. So every free name has to be rebound, and a name that cannot be is a stub that
/// does not compile.
///
/// This project has measured what that costs when it goes wrong — 145 of 163 emitted laws failing
/// to compile — so the rule here is **rebind or decline**, never rebind partially and hope.
///
/// ## Why this is not `replacingOccurrences`
///
/// Three ways a naive replace corrupts the text, all of which occur in the measured corpus:
///
/// - **Substrings of longer identifiers.** Binding `s` and replacing it blindly turns
///   `source.hasPrefix` into `<value>ource.ha<value>Prefix`. Identifiers are matched whole.
/// - **Member names.** In `other.count`, `other` is a parameter and `count` is a member *of* it.
///   Rebinding `count` would be meaningless; a name preceded by `.` is left alone.
/// - **String literals.** `hasPrefix("source")` contains the letters of a parameter name inside a
///   literal, and rewriting there changes what the code *tests for*. Literals are skipped whole,
///   escapes included.
///
/// ## Argument labels are left alone, and that is a limit rather than a rule
///
/// An identifier immediately followed by `:` is treated as an argument label and neither rebound
/// nor counted as unbound. That is right for `f(from: x)` and wrong for a dictionary literal
/// `[key: value]` used as a value, where `key` would silently survive unbound. No such condition
/// occurs in the 156 measured sites; if one appears it emits a stub that does not compile, which
/// is why it is written down here rather than left as an assumption.
public enum GuardDomainRebinding {

    /// Names that need no binding because they mean the same thing in any scope.
    ///
    /// Deliberately short. Every other free name must be bound or the rewrite declines — a
    /// permissive list here would let `_fastPath`, `_root` and `String` through, and those are
    /// exactly the 27 of 156 sites the feasibility measurement found unbindable.
    static let selfEvidentNames: Set<String> = ["true", "false", "nil"]

    /// `text` with every free identifier replaced by its binding, or `nil` when one has none.
    ///
    /// - Parameter bindings: free identifier → the expression a test uses for it. Typically each
    ///   parameter's internal name mapped to its drawn value, `self` to the drawn receiver, and
    ///   `Self` to the declaring type.
    public static func rebind(_ text: String, bindings: [String: String]) -> String? {
        var output = ""
        var declined = false
        scan(text) { token in
            switch token {
            case .verbatim(let piece):
                output += piece

            case .freeIdentifier(let name):
                if let bound = bindings[name] {
                    output += bound
                } else if selfEvidentNames.contains(name) {
                    output += name
                } else {
                    declined = true
                }
            }
        }
        return declined ? nil : output
    }

    /// Every free identifier in `text` that has no binding — what a decline reason names.
    ///
    /// Separate from `rebind` so a caller can *say* which name defeated it rather than reporting
    /// that something did. A decline a reader cannot act on is the failure
    /// `StubApplicationArity` exists to prevent one layer up.
    public static func unboundNames(in text: String, bindings: [String: String]) -> [String] {
        var unbound: [String] = []
        scan(text) { token in
            guard case .freeIdentifier(let name) = token,
                  bindings[name] == nil,
                  !selfEvidentNames.contains(name),
                  !unbound.contains(name) else { return }
            unbound.append(name)
        }
        return unbound
    }

    /// One piece of scanned text: either something to copy through, or a free identifier.
    private enum Token {
        case verbatim(String)
        case freeIdentifier(String)
    }

    /// Walk `text` once, handing each piece to `emit`.
    ///
    /// String literals are consumed whole — including `\"` escapes — before any identifier
    /// matching happens, so nothing inside one is ever seen as a name.
    private static func scan(_ text: String, emit: (Token) -> Void) {
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                let literal = consumeStringLiteral(characters, from: &index)
                emit(.verbatim(literal))
                continue
            }

            // A NUMBER is consumed whole, and that is not a tidiness point: `0x2F` scans as the
            // digit `0` followed by something starting with a letter, so a scanner that only
            // special-cases identifiers reads `x2F` as a free name and declines a site over a hex
            // literal. Found by this type's own test rather than by a corpus run.
            if character.isNumber {
                emit(.verbatim(consumeNumericLiteral(characters, from: &index)))
                continue
            }

            guard character.isLetter || character == "_" else {
                emit(.verbatim(String(character)))
                index += 1
                continue
            }

            let start = index
            while index < characters.count,
                  characters[index].isLetter || characters[index].isNumber || characters[index] == "_" {
                index += 1
            }
            let name = String(characters[start ..< index])
            // A member (`other.count`) or a labelled argument (`from:`) keeps its own spelling:
            // neither names a value the test has to supply.
            let isMember = start > 0 && characters[start - 1] == "."
            let isLabel = index < characters.count && characters[index] == ":"
            emit(isMember || isLabel ? .verbatim(name) : .freeIdentifier(name))
        }
    }

    /// The numeric literal starting at `index` — `42`, `0x2F`, `1_000`, `3.5`, `1e9`.
    ///
    /// Letters are consumed because a radix prefix and an exponent carry them; a `.` only when a
    /// digit follows, so `2.description` still scans as a number and a member rather than as one
    /// malformed token.
    private static func consumeNumericLiteral(_ characters: [Character], from index: inout Int) -> String {
        var literal = ""
        while index < characters.count {
            let character = characters[index]
            let isDecimalPoint = character == "."
                && index + 1 < characters.count
                && characters[index + 1].isNumber
            guard character.isNumber || character.isLetter || character == "_" || isDecimalPoint else { break }
            literal.append(character)
            index += 1
        }
        return literal
    }

    /// The string literal starting at `index`, advancing past its closing quote.
    private static func consumeStringLiteral(_ characters: [Character], from index: inout Int) -> String {
        var literal = String(characters[index])
        index += 1
        while index < characters.count {
            let character = characters[index]
            literal.append(character)
            index += 1
            if character == "\\", index < characters.count {
                literal.append(characters[index])
                index += 1
                continue
            }
            if character == "\"" { break }
        }
        return literal
    }
}
