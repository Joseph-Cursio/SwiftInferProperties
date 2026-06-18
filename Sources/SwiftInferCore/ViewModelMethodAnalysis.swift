import SwiftSyntax

/// PROTOTYPE — the raw mutation signals collected from a single method
/// body, resolved against the enclosing type's stored fields in a second
/// pass (`ViewModelDiscoverer`). Kept signature-light: which identifiers
/// the body *assigns to*, which identifiers it calls a *mutator* on, and
/// which *self-methods* it calls (for transitive action detection).
struct ViewModelMethodSignals: Equatable {
    /// Root identifiers on the left of an assignment (`x = …`, `x += …`):
    /// `self.foo = y` and `foo = y` both record `foo`.
    var assignedRoots: Set<String> = []
    /// Receivers of a mutating member call (`foo.removeAll()`,
    /// `self.foo.append(…)` record `foo`).
    var mutatorCallReceivers: Set<String> = []
    /// Names of same-object method calls (`bar(…)` / `self.bar(…)` record
    /// `bar`) — used to mark a method as an action when it drives another
    /// action.
    var calledMethodNames: Set<String> = []
}

/// PROTOTYPE — curated set of standard-library / common mutating method
/// names. A call `storedField.<name>(…)` is treated as a state mutation.
/// Read-only members (`map`/`filter`/`contains`/`first`/…) are excluded,
/// so a method that only *queries* a collection is not mis-flagged as an
/// action. Extended as real corpora demand (the same conservative,
/// curated posture as the algebraic templates' vocabulary lists).
enum ViewModelMutatorNames {
    static let curated: Set<String> = [
        "removeAll", "append", "insert", "remove", "removeFirst", "removeLast",
        "popFirst", "popLast", "removeValue", "updateValue",
        "sort", "reverse", "shuffle", "swapAt",
        "toggle", "formUnion", "formIntersection", "formSymmetricDifference",
        "subtract", "subtractInPlace", "merge", "negate"
    ]
}

/// PROTOTYPE — walks one method body collecting `ViewModelMethodSignals`.
/// Single recursive pass; the parser leaves operators unfolded, so
/// assignments surface as `SequenceExprSyntax` containing an
/// `AssignmentExprSyntax` (`=`) or a compound-assign `BinaryOperatorExprSyntax`
/// (`+=`, `-=`, …).
final class ViewModelMethodBodyWalker: SyntaxVisitor {

    private(set) var signals = ViewModelMethodSignals()

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        for (index, element) in elements.enumerated() where index > 0 {
            if Self.isAssignmentOperator(element),
               let root = Self.rootIdentifier(of: elements[index - 1]) {
                signals.assignedRoots.insert(root)
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression
        if let member = callee.as(MemberAccessExprSyntax.self) {
            let methodName = member.declName.baseName.text
            if let base = member.base, ViewModelMutatorNames.curated.contains(methodName),
               let receiver = Self.rootIdentifier(of: base) {
                // `foo.removeAll()` — foo is mutated.
                signals.mutatorCallReceivers.insert(receiver)
            } else if let base = member.base,
                      base.as(DeclReferenceExprSyntax.self)?.baseName.text == "self" {
                // `self.bar(…)` — a same-object method call.
                signals.calledMethodNames.insert(methodName)
            }
        } else if let ref = callee.as(DeclReferenceExprSyntax.self) {
            // Bare `bar(…)` — a same-object method call (or a free
            // function; the second-pass intersection with the type's own
            // method names filters free functions out).
            signals.calledMethodNames.insert(ref.baseName.text)
        }
        return .visitChildren
    }

    // MARK: - Helpers

    /// `true` for a plain `=` (`AssignmentExprSyntax`) or a compound
    /// assign (`+=`, `-=`, `*=`, …) — but NOT a comparison (`==`, `!=`,
    /// `<=`, `>=`).
    static func isAssignmentOperator(_ element: ExprSyntax) -> Bool {
        if element.is(AssignmentExprSyntax.self) { return true }
        guard let binary = element.as(BinaryOperatorExprSyntax.self) else { return false }
        let operatorText = binary.operator.text
        return operatorText.hasSuffix("=")
            && !["==", "!=", "<=", ">=", "==="].contains(operatorText)
    }

    /// The leftmost stored-field-relevant identifier of an expression.
    /// `foo` → `foo`; `self.foo` → `foo`; `self.foo.bar` → `foo`;
    /// `foo.bar` → `foo`; bare `self` / implicit-member `.x` → `nil`.
    static func rootIdentifier(of expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            let name = ref.baseName.text
            return name == "self" ? nil : name
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            guard let base = member.base else { return nil }
            if base.as(DeclReferenceExprSyntax.self)?.baseName.text == "self" {
                return member.declName.baseName.text
            }
            return rootIdentifier(of: base)
        }
        return nil
    }

    /// Run the walker over a method body and return the collected signals.
    static func signals(for body: CodeBlockSyntax) -> ViewModelMethodSignals {
        let walker = ViewModelMethodBodyWalker()
        walker.walk(body)
        return walker.signals
    }
}
