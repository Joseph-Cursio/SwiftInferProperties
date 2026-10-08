import SwiftSyntax

/// How one marker row tests its input: `contains`, `hasPrefix` or `hasSuffix`.
public enum MarkerTest: String, Sendable, Equatable {
    case contains, hasPrefix, hasSuffix

    func matches(_ text: String, literal: String) -> Bool {
        switch self {
        case .contains: return text.contains(literal)
        case .hasPrefix: return text.hasPrefix(literal)
        case .hasSuffix: return text.hasSuffix(literal)
        }
    }
}

/// One literal of a dispatch chain and the case it returns.
public struct MarkerRow: Sendable, Equatable {
    public let literal: String
    public let test: MarkerTest
    /// The returned expression as a test can spell it against the declared return type: `.comments`.
    public let result: String

    public init(literal: String, test: MarkerTest, result: String) {
        self.literal = literal
        self.test = test
        self.result = result
    }
}

/// A `String -> E` function written as a keyword table (SwiftInferProperties#644):
///
/// ```swift
/// let lower = ruleName.lowercased()
/// if lower.contains("comment") || lower.contains("doc") { return .comments }
/// if lower.contains("sort") || lower.contains("mark") { return .organization }
/// return .idiomatic
/// ```
///
/// The rows are in source order, which is precedence: a name matching two rows takes the first.
public struct MarkerDispatch: Sendable, Equatable {
    public let rows: [MarkerRow]
    /// `true` when the chain tests a `lowercased()` binding, so case is part of the law.
    public let isCaseInsensitive: Bool

    public init(rows: [MarkerRow], isCaseInsensitive: Bool) {
        self.rows = rows
        self.isCaseInsensitive = isCaseInsensitive
    }

    /// The index of the row `name` dispatches to, read the way the chain reads it.
    public func dispatchedRow(for name: String) -> Int? {
        let text = isCaseInsensitive ? name.lowercased() : name
        return rows.firstIndex { $0.test.matches(text, literal: $0.literal) }
    }

    /// Letters that appear in no literal, so an affix built from them cannot spell a marker or
    /// complete one across the boundary. Lowercase, and checked against lowercased literals, so
    /// their uppercase forms are neutral for a case-insensitive chain too.
    public var neutralLetters: [Character] {
        let used = Set(rows.flatMap { $0.literal.lowercased() })
        return Array("qzjxkvwyfg").filter { !used.contains($0) }
    }

    /// The names a test can check, each with the case it must dispatch to, and the literals that
    /// cannot be checked because an EARLIER row claims them.
    ///
    /// A row is checkable when its bare literal dispatches to it. That is also enough for every
    /// affixed form: affix letters appear in no literal, so they can complete no earlier marker.
    public func probes() -> (checkable: [(name: String, result: String)], shadowed: [String]) {
        var checkable: [(name: String, result: String)] = []
        var shadowed: [String] = []
        let neutral = neutralLetters
        let before = neutral.first.map { String($0) } ?? ""
        let after = neutral.dropFirst().first.map { String($0) } ?? before
        for (index, row) in rows.enumerated() {
            guard dispatchedRow(for: row.literal) == index else {
                shadowed.append(row.literal)
                continue
            }
            var names = [row.literal]
            let affixed: String
            switch row.test {
            case .contains: affixed = before + row.literal + after
            case .hasPrefix: affixed = row.literal + after
            case .hasSuffix: affixed = before + row.literal
            }
            if affixed != row.literal { names.append(affixed) }
            if isCaseInsensitive { names.append(affixed.uppercased()) }
            for name in names where !checkable.contains(where: { $0.name == name }) {
                checkable.append((name, row.result))
            }
        }
        return (checkable, shadowed)
    }
}

/// `primary(for: x) ?? fallback(for: x)` — a lookup fronting a fallback. When the fallback is a
/// dispatch chain, a test reaches it through this function and must skip names the lookup claims.
public struct FallbackDelegation: Sendable, Equatable {
    public let primaryName: String
    public let primaryLabel: String?
    public let fallbackName: String

    public init(primaryName: String, primaryLabel: String?, fallbackName: String) {
        self.primaryName = primaryName
        self.primaryLabel = primaryLabel
        self.fallbackName = fallbackName
    }
}

/// Reads `MarkerDispatch` and `FallbackDelegation` from function bodies. Both decline anything they
/// could not restate exactly.
public enum MarkerDispatchReader {

    /// The chain, when the body is: an optional `let l = p.lowercased()`, two or more
    /// `if <markers> { return <case> }`, then `return <case>`.
    public static func read(_ function: FunctionDeclSyntax) -> MarkerDispatch? {
        guard let parameter = soleStringParameter(of: function),
              let items = function.body?.statements.map(\.item), items.count >= 3 else {
            return nil
        }
        var subject = parameter
        var remaining = items[...]
        var isCaseInsensitive = false
        if let lowered = lowercasedBinding(items[0], of: parameter) {
            subject = lowered
            isCaseInsensitive = true
            remaining = remaining.dropFirst()
        }
        guard let last = remaining.last,
              let fallback = last.as(ReturnStmtSyntax.self)?.expression,
              caseExpression(fallback) != nil else {
            return nil
        }
        var rows: [MarkerRow] = []
        let branches = remaining.dropLast()
        guard branches.count >= 2 else { return nil }
        for item in branches {
            guard let branch = markerBranch(item, subject: subject) else { return nil }
            rows += branch
        }
        // A lowercased input never contains an uppercase literal: that row is dead, not a law.
        if isCaseInsensitive, rows.contains(where: { $0.literal != $0.literal.lowercased() }) { return nil }
        return MarkerDispatch(rows: rows, isCaseInsensitive: isCaseInsensitive)
    }

    /// `return primary(for: x) ?? fallback(for: x)`, or the same as an implicit return.
    public static func readDelegation(_ function: FunctionDeclSyntax) -> FallbackDelegation? {
        guard let parameter = soleStringParameter(of: function),
              let statements = function.body?.statements, statements.count == 1,
              let item = statements.first?.item else {
            return nil
        }
        let expression = item.as(ReturnStmtSyntax.self)?.expression
            ?? item.as(ExpressionStmtSyntax.self)?.expression
            ?? item.as(ExprSyntax.self)
        guard let sequence = expression?.as(SequenceExprSyntax.self) else { return nil }
        let elements = Array(sequence.elements)
        guard elements.count == 3,
              elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text == "??",
              let primary = singleArgumentCall(elements[0], passing: parameter),
              let fallback = singleArgumentCall(elements[2], passing: parameter) else {
            return nil
        }
        return FallbackDelegation(primaryName: primary.name, primaryLabel: primary.label, fallbackName: fallback.name)
    }

    // MARK: - Pieces

    private static func soleStringParameter(of function: FunctionDeclSyntax) -> String? {
        let parameters = function.signature.parameterClause.parameters
        guard parameters.count == 1, let parameter = parameters.first,
              parameter.type.trimmedDescription == "String" else { return nil }
        let name = (parameter.secondName ?? parameter.firstName).text
        return name == "_" ? nil : name
    }

    /// `let lower = name.lowercased()` → `lower`.
    private static func lowercasedBinding(_ item: CodeBlockItemSyntax.Item, of parameter: String) -> String? {
        guard let declaration = item.as(VariableDeclSyntax.self),
              declaration.bindings.count == 1,
              let binding = declaration.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
              call.arguments.isEmpty,
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "lowercased",
              member.base?.trimmedDescription == parameter else {
            return nil
        }
        return name
    }

    /// `if a || b || c { return .x }` → one row per marker, all returning `.x`.
    private static func markerBranch(_ item: CodeBlockItemSyntax.Item, subject: String) -> [MarkerRow]? {
        guard let ifExpr = item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self),
              ifExpr.elseBody == nil,
              ifExpr.conditions.count == 1,
              case .expression(let condition) = ifExpr.conditions.first?.condition,
              ifExpr.body.statements.count == 1,
              let returned = ifExpr.body.statements.first?.item.as(ReturnStmtSyntax.self)?.expression,
              let result = caseExpression(returned) else {
            return nil
        }
        var disjuncts: [ExprSyntax] = []
        if let sequence = condition.as(SequenceExprSyntax.self) {
            for (index, element) in sequence.elements.enumerated() {
                if index.isMultiple(of: 2) {
                    disjuncts.append(element)
                } else if element.as(BinaryOperatorExprSyntax.self)?.operator.text != "||" {
                    return nil
                }
            }
        } else {
            disjuncts = [condition]
        }
        var rows: [MarkerRow] = []
        for disjunct in disjuncts {
            guard let marker = marker(disjunct, subject: subject) else { return nil }
            rows.append(MarkerRow(literal: marker.literal, test: marker.test, result: result))
        }
        return rows
    }

    /// `subject.contains("x")`, `.hasPrefix("x")` or `.hasSuffix("x")` with a plain, non-empty literal.
    private static func marker(_ expression: ExprSyntax, subject: String) -> (literal: String, test: MarkerTest)? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.base?.trimmedDescription == subject,
              let test = MarkerTest(rawValue: member.declName.baseName.text),
              call.arguments.count == 1,
              let argument = call.arguments.first, argument.label == nil,
              let literal = argument.expression.as(StringLiteralExprSyntax.self),
              literal.segments.count == 1,
              let segment = literal.segments.first?.as(StringSegmentSyntax.self) else {
            return nil
        }
        let text = segment.content.text
        // An escape would be restated wrongly by a writer splicing the text back into a literal.
        guard !text.isEmpty, !text.contains("\\") else { return nil }
        return (text, test)
    }

    /// `.comments`, from `.comments` or `Category.comments`; `nil` for anything else.
    private static func caseExpression(_ expression: ExprSyntax) -> String? {
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.declName.argumentNames == nil else { return nil }
        let name = member.declName.baseName.text
        guard let base = member.base else { return "." + name }
        let baseText = base.trimmedDescription
        guard baseText.first?.isUppercase == true,
              baseText.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) else { return nil }
        return "." + name
    }

    /// `f(for: x)` or `Type.f(for: x)` passing exactly the parameter.
    private static func singleArgumentCall(
        _ expression: ExprSyntax,
        passing parameter: String
    ) -> (name: String, label: String?)? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.trailingClosure == nil,
              call.arguments.count == 1,
              let argument = call.arguments.first,
              argument.expression.trimmedDescription == parameter else {
            return nil
        }
        let name: String
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            name = reference.baseName.text
        } else if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                  let base = member.base?.trimmedDescription,
                  base == "Self" || base == "self" || base.first?.isUppercase == true {
            name = member.declName.baseName.text
        } else {
            return nil
        }
        return (name, argument.label?.text)
    }
}
