import SwiftSyntax

extension ExprSyntax {
    /// The trailing identifier of a reference or member-access expression.
    ///
    /// `foo` → `"foo"`, `a.b.foo` → `"foo"`, anything else → `nil`. Used by the
    /// assertion detectors to name the callee of a `FunctionCallExprSyntax` and by
    /// the domain extractors to name the producer/consumer in a call chain.
    ///
    /// Previously copy-pasted nine times as `calleeName(of:)` / `trailingIdentifier(of:)`.
    var trailingIdentifierName: String? {
        if let ref = self.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = self.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }
}
