import SwiftSyntax

// Copied from `Sources/SwiftInferCore/ReplacementChainClassifier.swift` at 74a385e3 (§1.1): `steps`, `step`,
// `apply` and `replacingAll`, with the two search constants. They are `internal` there, so they cannot be imported;
// copying them is what makes (a) the classifier's own reading. The function bodies are verbatim. The only edits are
// that `public` is dropped and `Step` is also `Codable`, so the census can write it out.
enum ReplacementChainClassifier {

    /// One `replacingOccurrences(of: pattern, with: replacement)` step.
    struct Step: Sendable, Equatable, Codable {
        let pattern: String
        let replacement: String
    }

    static let searchLength = 3
    static let alphabetCap = 9

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
