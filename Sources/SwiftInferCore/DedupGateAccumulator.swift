import SwiftSyntax

/// The mutating-accumulator veto (M8) for `DedupGateClassifier`.
///
/// A dedup gate makes the effect it *dominates* run at most once. But a handler
/// can also accumulate on an **ungated** path — a counter increment or a collection
/// append in the statements *before* the gate, which run on every invocation
/// including replays. `self.callCount += 1` before `if hasHandled { return }` grows
/// on each retry, so the handler is not idempotent even though the gate is real.
/// Effect-dominance (M7) catches an ungated *effect-verb call*; this catches an
/// ungated *mutation of stored state*, which is not a call.
///
/// Member-scoped for precision: only a compound-assign into a **member**
/// (`self.count += 1`, not a bare local `count += 1`) or an `.append` on a **member**
/// receiver (`self.items.append(…)`) counts — a local accumulator resets each call
/// and is not an observable effect.
extension DedupGateClassifier {

    /// Whether any statement strictly before the gate mutates stored state — an
    /// accumulation the gate does not dominate.
    static func hasUngatedAccumulator(
        _ statements: [CodeBlockItemSyntax],
        beforeGate gateIndex: Int
    ) -> Bool {
        statements[..<gateIndex].contains { item in
            let finder = AccumulatorFinder()
            finder.walk(Syntax(item))
            return finder.found
        }
    }
}

/// Finds a stored-state accumulation: a member compound-assign or a member
/// `.append`, ignoring nested closures / functions.
private final class AccumulatorFinder: SyntaxVisitor {
    private(set) var found = false

    static let compoundOps: Set<String> = [
        "+=", "-=", "*=", "/=", "%=", "&+=", "&-=", "&*="
    ]

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        // `self.count += 1` — SwiftSyntax leaves the sequence unfolded, so the
        // operator sits between its operands: [member, `+=`, value].
        let elements = Array(node.elements)
        for index in elements.indices where index > 0 {
            guard let binaryOperator = elements[index].as(BinaryOperatorExprSyntax.self),
                  Self.compoundOps.contains(binaryOperator.operator.text) else {
                continue
            }
            if elements[index - 1].is(MemberAccessExprSyntax.self) {
                found = true
                return .skipChildren
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // `self.items.append(x)` — a member's collection grows.
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "append",
           member.base?.is(MemberAccessExprSyntax.self) == true {
            found = true
            return .skipChildren
        }
        return .visitChildren
    }

    override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}
