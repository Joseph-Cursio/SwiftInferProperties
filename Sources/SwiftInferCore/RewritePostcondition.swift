import SwiftSyntax

/// What a string-rewriting function's body guarantees about its output: the tokens it removes.
///
/// ```swift
/// static func safeAlias(_ name: String) -> String {
///     name.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
/// }
/// ```
///
/// never returns a `-` or a space, and
///
/// ```swift
/// func parseCommaDelimitedList(_ string: String) -> [String] {
///     string.components(separatedBy: ",").compactMap { … trimmed, or nil … }
/// }
/// ```
///
/// never returns an element containing `,`. Both are read from the body, so the code satisfies them
/// today; what they catch is an edit that drops a replacement or changes the separator — the two
/// law-blind mutant shapes `docs/measurements/law-blind-mutants.md` names, which passed their
/// idempotence and totality laws.
public struct RewritePostcondition: Sendable, Equatable, Codable {

    public enum Guarantee: Sendable, Equatable, Codable {
        /// The returned `String` contains none of these tokens.
        case outputLacks([String])
        /// No element of the returned `[String]` contains this separator.
        case elementsLack(String)
    }

    public let parameterName: String
    public let guarantee: Guarantee

    public init(parameterName: String, guarantee: Guarantee) {
        self.parameterName = parameterName
        self.guarantee = guarantee
    }
}

/// Reads a `RewritePostcondition` off a unary `String` function whose whole body is the rewrite.
///
/// ## Two shapes, both narrow on purpose
///
/// **A pure replacement chain** rooted at the parameter, every pattern and replacement a literal —
/// `ReplacementChainClassifier.steps`, the same extraction the idempotence gate uses. Only
/// single-character patterns are claimed, and only when nothing from their step on writes them back
/// (`absentPatterns`) — the one guarantee that holds for every input.
///
/// **A split on a literal separator**, optionally followed by one `map` / `compactMap` / `filter`
/// whose closure only trims, tests emptiness, or drops the element. Anything else in the closure could
/// put the separator back, so it is refused.
public enum RewritePostconditionReader {

    public static func read(_ function: FunctionDeclSyntax) -> RewritePostcondition? {
        let parameters = function.signature.parameterClause.parameters
        guard parameters.count == 1, let parameter = parameters.first,
              parameter.type.trimmedDescription == "String",
              let returnType = function.signature.returnClause?.type.trimmedDescription,
              let statements = function.body?.statements, statements.count == 1,
              let item = statements.first?.item,
              let expression = expression(of: item) else { return nil }
        let name = (parameter.secondName ?? parameter.firstName).text
        guard name != "_" else { return nil }
        if returnType == "String" {
            return chainGuarantee(expression, parameter: name)
        }
        if returnType == "[String]" {
            return splitGuarantee(expression, parameter: name)
        }
        return nil
    }

    private static func expression(of item: CodeBlockItemSyntax.Item) -> ExprSyntax? {
        item.as(ReturnStmtSyntax.self)?.expression
            ?? item.as(ExpressionStmtSyntax.self)?.expression
            ?? item.as(ExprSyntax.self)
    }

    // MARK: - Replacement chain

    static func chainGuarantee(_ expression: ExprSyntax, parameter: String) -> RewritePostcondition? {
        guard let steps = ReplacementChainClassifier.steps(of: expression, root: parameter) else { return nil }
        let absent = absentPatterns(steps)
        guard !absent.isEmpty else { return nil }
        return RewritePostcondition(parameterName: parameter, guarantee: .outputLacks(absent))
    }

    /// The single-character patterns no output of the chain can contain, in chain order.
    ///
    /// **A character, and only a character, is provably absent.** When a step replaces exactly `c` and
    /// no replacement from that step on contains `c`, no output contains `c` for ANY input: every `c`
    /// is rewritten away, nothing later writes one, and removing text can join characters but never
    /// create one that is gone. A longer pattern has no such guarantee — removing an inner `<mark>`
    /// from `<ma<mark>rk>` forms a new one — and a bounded search over short strings cannot see
    /// that: the first version evaluated the chain and claimed `stripMarkTags` never returns `<mark>`,
    /// a false law found by hand-checking the census.
    static func absentPatterns(_ steps: [ReplacementChainClassifier.Step]) -> [String] {
        var absent: [String] = []
        for (index, step) in steps.enumerated() where step.pattern.count == 1 {
            let reintroduced = steps[index...].contains { $0.replacement.contains(step.pattern) }
            if !reintroduced, !absent.contains(step.pattern) { absent.append(step.pattern) }
        }
        return absent
    }

    // MARK: - Split

    static func splitGuarantee(_ expression: ExprSyntax, parameter: String) -> RewritePostcondition? {
        var current = expression
        // One element-preserving step on top of the split, at most.
        if let call = current.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           ["map", "compactMap", "filter"].contains(member.declName.baseName.text) {
            let closure = call.trailingClosure ?? call.arguments.first?.expression.as(ClosureExprSyntax.self)
            guard let closure, closureOnlyNarrows(closure),
                  let base = member.base else { return nil }
            current = base
        }
        guard let call = current.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == parameter,
              let separator = splitSeparator(member.declName.baseName.text, call.arguments),
              !separator.isEmpty else { return nil }
        return RewritePostcondition(parameterName: parameter, guarantee: .elementsLack(separator))
    }

    private static func splitSeparator(_ name: String, _ arguments: LabeledExprListSyntax) -> String? {
        let first = arguments.first
        switch (name, first?.label?.text) {
        case ("components", "separatedBy"), ("split", "separator"):
            return first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue

        default:
            return nil
        }
    }

    /// Whether a closure can only shorten or drop an element: every identifier it uses is from a small
    /// set of trimming and emptiness words, and it writes no string literal it could splice back in.
    static func closureOnlyNarrows(_ closure: ClosureExprSyntax) -> Bool {
        let allowed: Set<String> = [
            "let", "var", "return", "nil", "true", "false", "if", "else", "guard",
            "trimmingCharacters", "in", "whitespaces", "whitespacesAndNewlines", "newlines",
            "isEmpty", "String", "Substring", "count"
        ]
        let text = closure.statements.trimmedDescription
        guard !text.contains("\"") else { return false }
        var local: Set<String> = []
        if let signature = closure.signature {
            let names = signature.trimmedDescription.split { !($0.isLetter || $0.isNumber || $0 == "_") }
            local.formUnion(names.map(String.init))
        }
        for token in text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == "$") }) {
            let word = String(token)
            if word.hasPrefix("$") || word.first?.isNumber == true || allowed.contains(word) { continue }
            // A local bound inside the closure (`let item = …`) is allowed; it is still an element.
            if text.contains("let \(word) =") || text.contains("var \(word) =") || local.contains(word) { continue }
            return false
        }
        return true
    }
}
