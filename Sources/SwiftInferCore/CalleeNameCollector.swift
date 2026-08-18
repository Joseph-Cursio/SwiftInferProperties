import SwiftSyntax

/// Free-shape callee names reached from a function body.
///
/// **Free shape only, and that is the soundness boundary.** `foo(x)` names a declaration;
/// `receiver.foo(x)` names a *member*, and this toolchain cannot resolve which type's
/// member without an index — `swift-syntax` gives no call graph, which open item 38
/// records as the cap on this whole family. Joining on member names would match
/// `encode` on any type against `encode` on any other. Member shape is therefore not
/// collected at all rather than collected and filtered, so no later consumer can reach
/// for it by mistake.
///
/// **Nested function names are excluded.** A call to a locally-declared helper resolves
/// inside this body, not to a package declaration, and admitting it would let a local
/// helper's name collide with a refuted top-level one. Measured in
/// `PurityFixpointCensusMeasuredTests`, where omitting this check was one of the causes
/// of a 61% false-positive rate on its first run.
public final class CalleeNameCollector: SyntaxVisitor {

    private var found: Set<String> = []
    private var nestedFunctionNames: Set<String> = []

    /// Free-shape callee names, sorted so the field they land on is stable across runs —
    /// PRD §16 #6's byte-identical-reproducibility guarantee reaches this.
    public var names: [String] { found.subtracting(nestedFunctionNames).sorted() }

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        nestedFunctionNames.insert(node.name.text)
        return .visitChildren
    }

    override public func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let name = Self.freeCalleeName(of: node.calledExpression) { found.insert(name) }
        return .visitChildren
    }

    /// The callee's name when the call is free-shape, unwrapping the spellings that wrap
    /// one — `Foo<Bar>(…)`, `(foo)(…)`, `foo?(…)`, `foo!(…)`. A member access returns
    /// `nil`: it is a call, but not one this collector can resolve.
    static func freeCalleeName(of expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if expression.is(MemberAccessExprSyntax.self) {
            return nil
        }
        if let specialized = expression.as(GenericSpecializationExprSyntax.self) {
            return freeCalleeName(of: specialized.expression)
        }
        if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
           let only = tuple.elements.first {
            return freeCalleeName(of: only.expression)
        }
        if let optional = expression.as(OptionalChainingExprSyntax.self) {
            return freeCalleeName(of: optional.expression)
        }
        if let forced = expression.as(ForceUnwrapExprSyntax.self) {
            return freeCalleeName(of: forced.expression)
        }
        return nil
    }
}
