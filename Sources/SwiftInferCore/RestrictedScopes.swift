import Foundation
import SwiftParser
import SwiftSyntax

/// **Every `private` / `fileprivate` keyword standing between a test and a declaration** — the
/// declaration's own, and every enclosing type or extension's — each with the line it sits on.
///
/// `AccessRestriction` says *why* a subject is unreachable; this says *what to delete*. The two
/// differ because one restriction can have several keywords behind it, and a patch that deletes
/// only one of them compiles and changes nothing:
///
/// ```swift
/// private final class SensitiveReferenceFinder: SyntaxVisitor {   // ← blocks
///     private func containsSensitiveWord(_ name: String) -> Bool   // ← also blocks
/// }
/// ```
///
/// The stub header used to read the declaration's own line alone, so it printed `Delete private`
/// for the member while the sentence above it said widening the member was a no-op. And where the
/// member carries no keyword of its own —
///
/// ```swift
/// public struct ERScript { … }
/// private extension ERScript {
///     static func sanitizeType(_ raw: String) -> String
/// }
/// ```
///
/// — it printed no edit at all, and the remedy told the reader to widen an enclosing *type* that
/// is already `public`. The keyword is on the **extension**. Measured on the 22 September census:
/// all 8 of SwiftUMLStudio's access-first stubs are this shape.
///
/// Read from the source rather than from the scanner's enclosing-type stack, because the stack
/// keeps a verdict per scope and not the line its keyword is on — and the line is the answer.
/// ⚠ **Same known bound as `AccessRestriction.enclosingTypeNotVisibleToTests`**: a member of an
/// *unmarked* extension of a `private` type is not seen, because the type's own declaration is a
/// different declaration, possibly in another file.
public enum RestrictedScopes {

    /// One keyword to delete.
    public struct Scope: Sendable, Equatable {
        /// `private` or `fileprivate`.
        public let modifier: String
        /// 1-based line the keyword sits on.
        public let line: Int
        /// `extension ERScript`, `class SensitiveReferenceFinder`, or `nil` for the declaration
        /// itself.
        public let enclosing: String?

        public init(modifier: String, line: Int, enclosing: String?) {
            self.modifier = modifier
            self.line = line
            self.enclosing = enclosing
        }

        /// Whether deleting this keyword widens more than the subject — true of an extension,
        /// whose every member takes its default access from the extension's modifier.
        public var widensSiblings: Bool {
            enclosing?.hasPrefix("extension ") == true
        }
    }

    /// Every restricting keyword for the declaration at `line`, outermost first, or `[]` when
    /// none is found — including when no declaration contains the line.
    public static func blocking(declarationAt line: Int, in source: String) -> [Scope] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "", tree: tree)
        let finder = DeclarationFinder(line: line, converter: converter)
        finder.walk(tree)
        guard let declaration = finder.innermost else { return [] }

        var scopes: [Scope] = []
        if let own = restriction(in: modifiers(of: declaration), converter: converter) {
            scopes.append(Scope(modifier: own.modifier, line: own.line, enclosing: nil))
        }
        var parent = declaration.parent
        while let node = parent {
            if let (label, list) = enclosingScope(node),
               let found = restriction(in: list, converter: converter) {
                scopes.append(Scope(modifier: found.modifier, line: found.line, enclosing: label))
            }
            parent = node.parent
        }
        return scopes.reversed()
    }

    private static func modifiers(of declaration: DeclSyntax) -> DeclModifierListSyntax? {
        declaration.asProtocol(WithModifiersSyntax.self)?.modifiers
    }

    /// The keyword in `list`, ignoring `private(set)` — a setter restriction does not stop a test
    /// from naming or calling anything.
    private static func restriction(
        in list: DeclModifierListSyntax?,
        converter: SourceLocationConverter
    ) -> (modifier: String, line: Int)? {
        guard let list else { return nil }
        for modifier in list where modifier.detail == nil {
            let name = modifier.name.text
            if name == "private" || name == "fileprivate" {
                return (name, modifier.name.startLocation(converter: converter).line)
            }
        }
        return nil
    }

    private static func enclosingScope(_ node: Syntax) -> (String, DeclModifierListSyntax)? {
        if let decl = node.as(ExtensionDeclSyntax.self) {
            return ("extension \(decl.extendedType.trimmedDescription)", decl.modifiers)
        }
        if let decl = node.as(ClassDeclSyntax.self) {
            return ("class \(decl.name.text)", decl.modifiers)
        }
        if let decl = node.as(StructDeclSyntax.self) {
            return ("struct \(decl.name.text)", decl.modifiers)
        }
        if let decl = node.as(EnumDeclSyntax.self) {
            return ("enum \(decl.name.text)", decl.modifiers)
        }
        if let decl = node.as(ActorDeclSyntax.self) {
            return ("actor \(decl.name.text)", decl.modifiers)
        }
        return nil
    }
}

/// The innermost function, initializer, subscript or property whose extent covers the line.
private final class DeclarationFinder: SyntaxVisitor {
    let line: Int
    let converter: SourceLocationConverter
    private(set) var innermost: DeclSyntax?

    init(line: Int, converter: SourceLocationConverter) {
        self.line = line
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { consider(DeclSyntax(node)) }
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { consider(DeclSyntax(node)) }
    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind { consider(DeclSyntax(node)) }
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind { consider(DeclSyntax(node)) }

    private func consider(_ node: DeclSyntax) -> SyntaxVisitorContinueKind {
        let start = node.startLocation(converter: converter).line
        let end = node.endLocation(converter: converter).line
        guard start <= line, line <= end else { return .skipChildren }
        innermost = node
        return .visitChildren
    }
}
