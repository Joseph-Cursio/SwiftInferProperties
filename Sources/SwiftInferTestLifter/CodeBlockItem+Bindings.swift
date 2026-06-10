import SwiftSyntax

extension Collection where Element == CodeBlockItemSyntax {
    /// Map each `let`/`var x = <expr>` declaration in the block to
    /// `x → <expr>`, keyed by the first binding's identifier.
    ///
    /// Skips items that aren't single-identifier variable declarations with an
    /// initializer. Used by the assertion detectors to resolve the
    /// property-region bindings a test body references.
    ///
    /// Previously copy-pasted as `collectBindings(in:)` across five detectors.
    func bindingInitializers() -> [String: ExprSyntax] {
        var bindings: [String: ExprSyntax] = [:]
        for item in self {
            guard case .decl(let decl) = item.item,
                  let varDecl = decl.as(VariableDeclSyntax.self),
                  let firstBinding = varDecl.bindings.first,
                  let identifierPattern = firstBinding.pattern.as(IdentifierPatternSyntax.self),
                  let initializer = firstBinding.initializer?.value else {
                continue
            }
            bindings[identifierPattern.identifier.text] = initializer
        }
        return bindings
    }
}
