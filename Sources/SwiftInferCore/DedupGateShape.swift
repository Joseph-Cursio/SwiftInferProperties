import SwiftSyntax

/// A **dedup gate** in a side-effecting handler's body: the structural tell that
/// the handler is safe to run twice because an early branch short-circuits the
/// second run before it repeats the effect. Read by `ReplayIdempotenceTemplate`'s
/// Branch C (M2), which proposes a replay-idempotency property for a handler that
/// carries neither an `@ExternallyIdempotent` annotation nor an `IdempotencyKey`
/// parameter — the two shapes M1 could see — but *does* guard its effect.
///
/// The refutation is structural and needs no separate veto: a handler with no such
/// leading branch (the ungated buggy twin whose effect runs unconditionally) yields
/// `nil`, so Branch C never fires on it. No gate, no proposal.
public enum DedupGateShape: Sendable, Equatable {

    /// `if <dedupCheck>(<key>) { return … }` before the effect — an early return
    /// when the key has already been handled (`OrderCreatedHandler.handle`).
    /// Carries the key expression's root identifier when recoverable (`order`
    /// from `order.id`), for the property's "hold this fixed" hint.
    case earlyReturnDedup(keyRoot: String?)

    /// `if let hit = <fetch>(…) { return hit }` — fetch an existing row under the
    /// key and return it on a hit, inserting only on a miss
    /// (`OfflineManager.download`).
    case fetchThenInsert
}

/// Reads a `DedupGateShape` off a handler body.
///
/// **Shallow and precise by design.** It inspects the body's TOP-LEVEL statements
/// only and returns the first gate it finds, because a dedup gate is an *early*
/// return — it precedes the effect. It matches a curated verb set rather than any
/// `if … return`, because a discovery tool's enemy is the false law: an
/// over-broad gate would propose replay-idempotency for every guard-and-return.
/// The verb lists are deliberately narrow (they cover the SwiftIdempotency
/// fixtures and little else); widening them is an M2+ recall decision to make
/// against a measured false-positive rate, not a guess to make now.
public enum DedupGateClassifier {

    /// Callee base names that read as "have we already handled this key?". Narrow
    /// on purpose — broad verbs (`contains`, `first`, `exists`) fire on ordinary
    /// guard-and-return code that is not a dedup gate.
    static let dedupVerbs: Set<String> = [
        "hasHandled", "isHandled", "alreadyHandled", "wasHandled",
        "isProcessed", "wasProcessed", "isDuplicate", "isKnown", "hasSeen"
    ]

    /// Callee base names that read as "fetch the existing row under this key".
    static let fetchVerbs: Set<String> = [
        "fetch", "find", "existing", "lookup"
    ]

    /// The first dedup gate among the body's top-level statements, or `nil`.
    public static func classify(body: CodeBlockSyntax) -> DedupGateShape? {
        for item in body.statements {
            guard let ifExpr = ifExpr(from: item), blockReturns(ifExpr.body) else {
                continue
            }
            if let shape = shape(of: ifExpr) {
                return shape
            }
        }
        return nil
    }

    /// The `IfExprSyntax` a top-level statement is, if any. A statement-position
    /// `if` is wrapped in an `ExpressionStmtSyntax` under `.stmt`; the `.expr`
    /// arm covers the value-position spelling too, so both are handled.
    private static func ifExpr(from item: CodeBlockItemSyntax) -> IfExprSyntax? {
        switch item.item {
        case let .expr(expression):
            return expression.as(IfExprSyntax.self)

        case let .stmt(statement):
            return statement.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self)

        case .decl:
            return nil
        }
    }

    private static func shape(of ifExpr: IfExprSyntax) -> DedupGateShape? {
        for element in ifExpr.conditions {
            switch element.condition {
            case let .expression(expr):
                // `if dedup.hasHandled(orderID: order.id) { return false }`
                if let call = firstCall(in: Syntax(expr), matching: dedupVerbs) {
                    return .earlyReturnDedup(keyRoot: keyRoot(of: call))
                }

            case let .optionalBinding(binding):
                // `if let existing = try context.fetch(descriptor).first { return existing }`
                if let value = binding.initializer?.value,
                   firstCall(in: Syntax(value), matching: fetchVerbs) != nil {
                    return .fetchThenInsert
                }

            default:
                continue
            }
        }
        return nil
    }

    /// The root identifier of the dedup call's first argument — `order` from
    /// `order.id`. `nil` when the argument is not a simple reference/member chain.
    private static func keyRoot(of call: FunctionCallExprSyntax) -> String? {
        guard let firstArgument = call.arguments.first?.expression else { return nil }
        return rootIdentifier(of: firstArgument)
    }

    private static func rootIdentifier(of expr: ExprSyntax) -> String? {
        if let member = expr.as(MemberAccessExprSyntax.self), let base = member.base {
            return rootIdentifier(of: base)
        }
        if let call = expr.as(FunctionCallExprSyntax.self) {
            return rootIdentifier(of: call.calledExpression)
        }
        return expr.as(DeclReferenceExprSyntax.self)?.baseName.text
    }

    /// The first call in `subtree` whose callee base name is in `verbs`.
    private static func firstCall(
        in subtree: Syntax,
        matching verbs: Set<String>
    ) -> FunctionCallExprSyntax? {
        let finder = CallVerbFinder(verbs: verbs)
        finder.walk(subtree)
        return finder.match
    }

    /// Whether `block` contains a `return`, not counting returns nested inside a
    /// closure or inner function (those return from something else).
    private static func blockReturns(_ block: CodeBlockSyntax) -> Bool {
        let finder = ReturnFinder()
        finder.walk(block)
        return finder.found
    }
}

/// Finds the first `FunctionCallExprSyntax` whose callee base name is in `verbs`.
private final class CallVerbFinder: SyntaxVisitor {
    private let verbs: Set<String>
    private(set) var match: FunctionCallExprSyntax?

    init(verbs: Set<String>) {
        self.verbs = verbs
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if match == nil, let baseName = calleeBaseName(node.calledExpression), verbs.contains(baseName) {
            match = node
            return .skipChildren
        }
        return .visitChildren
    }

    private func calleeBaseName(_ expr: ExprSyntax) -> String? {
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return expr.as(DeclReferenceExprSyntax.self)?.baseName.text
    }
}

/// Detects a `return` in a block, ignoring returns inside nested closures /
/// functions (which return from those, not the handler).
private final class ReturnFinder: SyntaxVisitor {
    private(set) var found = false

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
        found = true
        return .skipChildren
    }

    override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}
