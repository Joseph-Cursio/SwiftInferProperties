import SwiftSyntax

/// **A replacement chain that re-applies its own rewrite** — the escaper whose idempotence law is false.
///
/// `HTMLEscaping.escape` is `text.replacingOccurrences(of: "&", with: "&amp;")…`: its output contains
/// `&` again, so escaping twice escapes the escape — `&` → `&amp;` → `&amp;amp;`. `idempotence`
/// applies to every `(T) -> T`, so every such chain was proposed the law, and the stubs passed only
/// because the string generator never draws `&`.
///
/// ## Decided by EVALUATING the chain, never by a text rule
///
/// The obvious rule — *not idempotent when some replacement contains some pattern* — is wrong in one
/// direction: `x → y` then `y → z` has an output containing a later pattern and IS idempotent,
/// because the later step rewrites it in the same pass. So the chain is run: `f(f(s)) == f(s)` over
/// every string up to length 3 drawn from the chain's own characters plus a neutral one. That is
/// exact on the domain it covers, and a witness it returns is a real counterexample.
///
/// ## Measured before it was built
///
/// `docs/measurements/replacement-chain-idempotence-census.md`: **0 pure chains in 20 library
/// corpora; 10 in the funnel's application repositories — 5 re-escape, 5 do not.** The same
/// evaluation agreed 9 of 9 with executing the laws against each subject's own literals. It costs no
/// laws: a chain that IS idempotent keeps its law.
///
/// ## Deliberately narrow
///
/// Only a body that is ENTIRELY the chain, rooted at the function's own parameter or at `self`, with
/// every pattern and replacement a plain string literal. A `switch`-based mapping (`mimeType`) or a
/// character loop (`GlobTool.translate`) is false for the same underlying reason — its output is a
/// different language from its input — and is not touched here.
public enum ReplacementChainClassifier {

    /// One `replacingOccurrences(of: pattern, with: replacement)` step.
    public struct Step: Sendable, Equatable {
        public let pattern: String
        public let replacement: String
    }

    /// Longest string the evaluation tries. Length 3 over the chain's own alphabet reaches every
    /// witness the census found; the alphabet is capped so the search stays in the hundreds.
    static let searchLength = 3
    static let alphabetCap = 9

    /// `.reappliesItsRewrite` when `result` is a pure replacement chain rooted at `root` (a
    /// parameter name, or `nil` for `self`) that is not idempotent; `nil` otherwise.
    static func shape(of result: ExprSyntax, root: String?) -> IdempotenceReturnShape? {
        guard let steps = steps(of: result, root: root),
              let witness = counterexample(steps) else {
            return nil
        }
        return .reappliesItsRewrite(witness: witness)
    }

    /// The steps, innermost first, when `expression` is nothing but a replacement chain on `root`.
    static func steps(of expression: ExprSyntax, root: String?) -> [Step]? {
        var collected: [Step] = []
        var current = expression
        while true {
            guard let call = current.as(FunctionCallExprSyntax.self),
                  let step = step(of: call) else {
                break
            }
            collected.append(step)
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
                guard let base = member.base else { return nil }
                current = base
            } else if call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
                == "replacingOccurrences" {
                // Implicit `self`: `var x: String { replacingOccurrences(of:…) }`.
                return collected.isEmpty || root != nil ? nil : collected.reversed()
            } else {
                return nil
            }
        }
        guard !collected.isEmpty else { return nil }
        let rootName = current.as(DeclReferenceExprSyntax.self)?.baseName.text
        let rootedAtSelf = current.is(DeclReferenceExprSyntax.self) && rootName == "self"
        guard (root == nil && rootedAtSelf) || (root != nil && rootName == root) else {
            return nil
        }
        return collected.reversed()
    }

    /// The `(pattern, replacement)` of one `replacingOccurrences(of:with:)` call, both literals.
    private static func step(of call: FunctionCallExprSyntax) -> Step? {
        let name = call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
            ?? call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        let arguments = Array(call.arguments)
        guard name == "replacingOccurrences",
              arguments.count == 2,
              arguments[0].label?.text == "of",
              arguments[1].label?.text == "with",
              let pattern = arguments[0].expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
              let replacement = arguments[1].expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
              !pattern.isEmpty else {
            return nil
        }
        return Step(pattern: pattern, replacement: replacement)
    }

    /// A string `s` with `f(f(s)) != f(s)`, or `nil` when none exists up to `searchLength`.
    static func counterexample(_ steps: [Step]) -> String? {
        var alphabet = Set(steps.flatMap { Array($0.pattern) + Array($0.replacement) })
        alphabet.insert("x")
        let letters = Array(alphabet).sorted().prefix(alphabetCap)
        var frontier: [String] = [""]
        for _ in 0..<searchLength {
            var next: [String] = []
            for prefix in frontier {
                for letter in letters {
                    let candidate = prefix + String(letter)
                    let once = apply(steps, to: candidate)
                    if apply(steps, to: once) != once {
                        return candidate
                    }
                    next.append(candidate)
                }
            }
            frontier = next
        }
        return nil
    }

    /// The chain applied in order, each step replacing every non-overlapping occurrence left to right —
    /// `replacingOccurrences(of:with:)`'s literal semantics.
    static func apply(_ steps: [Step], to text: String) -> String {
        steps.reduce(text) { value, step in replacingAll(step.pattern, with: step.replacement, in: value) }
    }

    private static func replacingAll(_ pattern: String, with replacement: String, in text: String) -> String {
        let source = Array(text)
        let needle = Array(pattern)
        var output = ""
        var index = 0
        while index < source.count {
            if index + needle.count <= source.count, Array(source[index..<index + needle.count]) == needle {
                output += replacement
                index += needle.count
            } else {
                output.append(source[index])
                index += 1
            }
        }
        return output
    }
}
