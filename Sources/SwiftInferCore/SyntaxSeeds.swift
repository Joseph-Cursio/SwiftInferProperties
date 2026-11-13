import Foundation
import SwiftParser
import SwiftSyntax

/// Every `let` in a file bound to a string array or set literal, by name.
private final class StringTableCollector: SyntaxVisitor {
    private(set) var tables: [String: [String]] = [:]

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.bindingSpecifier.tokenKind == .keyword(.let) else { return .visitChildren }
        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let value = binding.initializer?.value,
                  let elements = SyntaxSeeds.stringElements(of: value) else { continue }
            tables[name] = elements
        }
        return .visitChildren
    }
}

/// The tokens and kinds one declaration's body names.
private final class SeedReader: SyntaxVisitor {
    let tables: [String: [String]]
    private(set) var tokens: [String] = []
    private(set) var kinds: [String] = []

    init(tables: [String: [String]]) {
        self.tables = tables
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        if let value = node.representedLiteralValue, SyntaxSeeds.isTokenLike(value) {
            tokens.append(value)
        }
        return .skipChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        tokens += (tables[node.baseName.text] ?? []).filter(SyntaxSeeds.isTokenLike)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              let argument = node.arguments.first?.expression else { return .visitChildren }
        switch member.declName.baseName.text {
        case "keyword":
            // `.keyword(.static)` → `static`
            if let keyword = argument.as(MemberAccessExprSyntax.self), keyword.base == nil {
                tokens.append(keyword.declName.baseName.text)
            }

        case "is", "as", "cast":
            // `.is(AwaitExprSyntax.self)` → `AwaitExprSyntax`
            if let metatype = argument.as(MemberAccessExprSyntax.self),
               metatype.declName.baseName.text == "self",
               let base = metatype.base?.trimmedDescription, base.hasSuffix("Syntax"),
               !SyntaxSeeds.categoryKinds.contains(base) {
                kinds.append(base)
            }

        default:
            break
        }
        return .visitChildren
    }
}

/// The tokens and node kinds a subject's body compares a syntax node against — what its syntax-corpus
/// draw should prefer (#684).
///
/// A predicate over a SwiftSyntax node returns `true` only for a particular token, name or shape:
/// `.keyword(.static)`, `"addTask"`, an attribute named `Published`, a parent that is an
/// `AwaitExprSyntax`. #665 measured that 252 of 273 red predicate stubs return only `false`, and that
/// the syntax corpus was where most of them drew. These are the subject's own words for the side it
/// never reached, so the corpus can prefer, and admit, the snippets that contain them —
/// `SubjectLiterals` does the same for a `String` parameter.
///
/// What is read, from the declaration covering the evidence line:
/// - **tokens:** every plain string literal of at most `maxLength` characters with no whitespace, so
///   it can equal one token's text; `x` for each `.keyword(.x)`; and, one hop away, the elements of a
///   same-file `let` / `static let` whose initializer is a string array or set literal, when the body
///   names it.
/// - **kinds:** `X` for each `.is(X.self)`, `.as(X.self)` or `.cast(X.self)` whose `X` ends in
///   `Syntax`.
///
/// Scoped, with the arms that measure it, in `docs/plans/predicate-reach-at-source-scope.md`.
public struct SyntaxSeeds: Sendable, Equatable {

    /// Most tokens, and most kinds, kept per subject.
    static let cap = 16
    /// Longest literal kept as a token.
    static let maxLength = 40

    public let tokens: [String]
    public let kinds: [String]

    public init(tokens: [String] = [], kinds: [String] = []) {
        self.tokens = tokens
        self.kinds = kinds
    }

    public var isEmpty: Bool { tokens.isEmpty && kinds.isEmpty }

    /// The seeds of the declaration covering `line` of `source`; empty when none covers it.
    public static func harvest(declarationAt line: Int, in source: String) -> Self {
        let tree = Parser.parse(source: source)
        let finder = DeclarationFinder(line: line, converter: SourceLocationConverter(fileName: "", tree: tree))
        finder.walk(tree)
        guard let declaration = finder.innermost else { return Self() }
        let constants = StringTableCollector(viewMode: .sourceAccurate)
        constants.walk(tree)
        let reader = SeedReader(tables: constants.tables)
        reader.walk(declaration)
        return Self(tokens: reader.tokens, kinds: reader.kinds).capped()
    }

    /// Every seed across a suggestion's evidence, reading each file once. Empty for evidence whose file
    /// cannot be read, which is every unit-test fixture.
    public static func of(_ suggestion: Suggestion) -> Self {
        var sources: [String: String] = [:]
        var allTokens: [String] = []
        var allKinds: [String] = []
        for evidence in suggestion.evidence where evidence.location.line > 0 {
            let file = evidence.location.file
            if sources[file] == nil {
                sources[file] = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
            }
            let seeds = harvest(declarationAt: evidence.location.line, in: sources[file] ?? "")
            allTokens += seeds.tokens
            allKinds += seeds.kinds
        }
        return Self(tokens: allTokens, kinds: allKinds).capped()
    }

    func capped() -> Self {
        Self(tokens: Self.unique(tokens), kinds: Self.unique(kinds))
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return Array(values.filter { seen.insert($0).inserted }.prefix(cap))
    }

    /// A literal that can equal one token's text: non-empty, short, and without whitespace.
    static func isTokenLike(_ value: String) -> Bool {
        !value.isEmpty && value.count <= maxLength && !value.contains(where: \.isWhitespace)
            && !value.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    /// The base categories. A concrete node's `syntaxNodeType` is never one, so the emitted draw could
    /// never match it, while every snippet holds one and would be admitted.
    static let categoryKinds: Set<String> = [
        "Syntax", "DeclSyntax", "ExprSyntax", "StmtSyntax", "TypeSyntax", "PatternSyntax",
    ]

    /// The plain strings of an array or set literal, or of `Set([...])`; `nil` for anything else.
    static func stringElements(of expression: ExprSyntax) -> [String]? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.trimmedDescription.hasPrefix("Set"),
           let argument = call.arguments.first?.expression {
            return stringElements(of: argument)
        }
        if let cast = expression.as(AsExprSyntax.self) {
            return stringElements(of: cast.expression)
        }
        guard let array = expression.as(ArrayExprSyntax.self) else { return nil }
        let values = array.elements.compactMap {
            $0.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        }
        return values.count == array.elements.count && !values.isEmpty ? values : nil
    }
}
