import Foundation
import SwiftParser
import SwiftSyntax

// The syntax walkers for `ModuleStateCensusMeasuredTests`. Split out only for the
// 400-line file cap; the reasoning that governs them lives in that suite's header.
// Internal rather than private because the suite's `collectorFires` control
// addresses `FileScopeVarCollector` directly — a collector that never fires and an
// empty corpus produce identical output, so the control has to reach it.

/// File-scope `var` names. Only `var` — a `let` cannot be mutated — and only at file
/// scope: a `static var` is a type member, and writes to those are already refuted by
/// `ReducerPurityAnalyzer`, so admitting them would double-count a covered case.
final class FileScopeVarCollector: SyntaxVisitor {

    private(set) var names: Set<String> = []
    private var depth = 0

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard depth == 0, node.bindingSpecifier.text == "var" else { return .visitChildren }
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                names.insert(pattern.identifier.text)
            }
        }
        return .visitChildren
    }

    // Anything nested inside a type or a function is not file scope.
    override func visit(_: StructDeclSyntax) -> SyntaxVisitorContinueKind { enter() }
    override func visit(_: ClassDeclSyntax) -> SyntaxVisitorContinueKind { enter() }
    override func visit(_: EnumDeclSyntax) -> SyntaxVisitorContinueKind { enter() }
    override func visit(_: ActorDeclSyntax) -> SyntaxVisitorContinueKind { enter() }
    override func visit(_: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind { enter() }
    override func visit(_: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { enter() }
    override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { enter() }

    override func visitPost(_: StructDeclSyntax) { depth -= 1 }
    override func visitPost(_: ClassDeclSyntax) { depth -= 1 }
    override func visitPost(_: EnumDeclSyntax) { depth -= 1 }
    override func visitPost(_: ActorDeclSyntax) { depth -= 1 }
    override func visitPost(_: ExtensionDeclSyntax) { depth -= 1 }
    override func visitPost(_: ProtocolDeclSyntax) { depth -= 1 }
    override func visitPost(_: FunctionDeclSyntax) { depth -= 1 }

    private func enter() -> SyntaxVisitorContinueKind {
        depth += 1
        return .visitChildren
    }
}

/// Writes to a named global inside a body, plus the names the body binds itself.
///
/// Three write shapes, because Swift spells assignment three ways and missing one
/// under-counts — the direction that flatters the tool:
/// `x = v` and `x += v` are both `InfixOperatorExprSyntax` (distinguished by whether
/// the operator is `AssignmentExprSyntax`), and `&x` is `InOutExprSyntax`.
final class ModuleStateWriteChecker: SyntaxVisitor {

    private let globals: Set<String>
    private(set) var written: Set<String> = []
    private(set) var memberCalled: Set<String> = []
    private(set) var locallyBound: Set<String> = []

    init(globals: Set<String>, viewMode: SyntaxTreeViewMode) {
        self.globals = globals
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                locallyBound.insert(pattern.identifier.text)
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        for parameter in node.signature.parameterClause.parameters {
            locallyBound.insert(parameter.secondName?.text ?? parameter.firstName.text)
        }
        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        // A closure mutating a capture is already refuted by `refuteIfCaptured`, so
        // its writes are not this census's subject and counting them would attribute
        // a covered case to the uncovered one.
        _ = node
        return .skipChildren
    }

    /// The **folded** form, present only after an `OperatorTable` has run.
    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if Self.isAssignment(Syntax(node.operator)) { noteWrite(node.leftOperand) }
        return .visitChildren
    }

    /// The **unfolded** form, which is what `Parser.parse` actually produces — and
    /// handling only the folded one is a blind instrument, not a narrow one.
    ///
    /// This census's first run asserted a base rate of 0 with a detector that could
    /// not see a single assignment: an operator sequence stays a flat
    /// `SequenceExprSyntax` until folded, so `counter += value` never becomes an
    /// `InfixOperatorExprSyntax` at all. `detectorFires` caught it on a synthetic
    /// witness. **`PurityInferrer` carries a comment warning about exactly this**, one
    /// file away — *"a visitor that only knows `InfixOperatorExprSyntax` sees no
    /// assignments at all"* — which is the second time today a documented trap was
    /// re-entered rather than read.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        for (index, element) in elements.enumerated() where index > 0 && Self.isAssignment(Syntax(element)) {
            noteWrite(elements[index - 1])
        }
        return .visitChildren
    }

    /// `=` and every compound form (`+=`, `*=`, …). A bare comparison such as `==`
    /// must not count, so the suffix test alone is not enough.
    static func isAssignment(_ node: Syntax) -> Bool {
        if node.is(AssignmentExprSyntax.self) { return true }
        guard let binary = node.as(BinaryOperatorExprSyntax.self) else { return false }
        let text = binary.operator.text
        return text.hasSuffix("=") && !["==", "!=", "<=", ">=", "==="].contains(text)
    }

    override func visit(_ node: InOutExprSyntax) -> SyntaxVisitorContinueKind {
        noteWrite(node.expression)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
           let base = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
           globals.contains(base) {
            memberCalled.insert(base)
        }
        return .visitChildren
    }

    /// The root identifier an assignment target rests on: `counter`, `cache[key]`
    /// and `settings.flag` all write through the same global.
    private func noteWrite(_ expression: ExprSyntax) {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            if globals.contains(reference.baseName.text) { written.insert(reference.baseName.text) }
            return
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base {
            noteWrite(base)
            return
        }
        if let subscriptExpr = expression.as(SubscriptCallExprSyntax.self) {
            noteWrite(subscriptExpr.calledExpression)
            return
        }
        if let forced = expression.as(ForceUnwrapExprSyntax.self) {
            noteWrite(forced.expression)
            return
        }
        if let optional = expression.as(OptionalChainingExprSyntax.self) {
            noteWrite(optional.expression)
        }
    }
}

/// Function declarations, for addressing a probe's subject by name.
final class ModuleStateFunctionFinder: SyntaxVisitor {
    private(set) var found: [FunctionDeclSyntax] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        found.append(node)
        return .visitChildren
    }
}
