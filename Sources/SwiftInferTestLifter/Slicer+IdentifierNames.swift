import SwiftInferCore
import SwiftSyntax

// Identifier collection, split out of `Slicer.swift` when the name-only guard below took that
// file past SwiftLint's 400-line cap. It is the backward slice's whole notion of "this statement
// reads that binding", so it lives on its own.

extension Slicer {

    /// Walks a sequence of expressions and returns the bare identifier
    /// names referenced inside (via `DeclReferenceExprSyntax`). Member
    /// accesses contribute their *base* — `encoder.encode(x)` adds
    /// `encoder` (not `encode`) and `x`. A key path contributes its
    /// subscript arguments and not its component names — `\.[index]`
    /// adds `index`, `\.id` adds nothing.
    static func identifierNames(in expressions: [ExprSyntax]) -> Set<String> {
        let collector = IdentifierCollector(viewMode: .sourceAccurate)
        for expression in expressions {
            collector.walk(expression)
        }
        return collector.names
    }

    private final class IdentifierCollector: SyntaxVisitor {
        var names: Set<String> = []

        /// ⚠ **A member's name and a key-path component's name read no binding.** Recording them
        /// let the `id` in `.map(\.id)` or `{ $0.id }` reach back to an unrelated `let id = 7`,
        /// which then moved into the property region and became a parameterized value. Every
        /// member name is skipped, `self.id` included: a test-local is never reached through
        /// `self`, and the base is visited on its own.
        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            if node.isNameOnlyPosition { return .skipChildren }
            names.insert(node.baseName.text)
            return .visitChildren
        }
    }
}
