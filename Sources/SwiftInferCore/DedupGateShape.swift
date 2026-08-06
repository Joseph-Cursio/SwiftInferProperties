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
    /// (`OfflineManager.download`). Also the *pre-fetched* form, where the fetch is
    /// an upstream `let` and the gate re-binds it (`MacCloud restoreFileVersion`).
    case fetchThenInsert

    /// `if <handledFlag> { return }` — an early return on a state property that
    /// reads as already-handled (`if file.isDeleted { return .ok }`,
    /// `MacCloud deleteFile`). The same semantic gate as `earlyReturnDedup`, but
    /// the "already handled?" question is answered by a stored flag rather than a
    /// dedup-store method call. Carries the flag name.
    case stateFlagGuard(flag: String?)
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
    /// `query` is included for the ORM idiom (`Model.query(on:)…first()`), which
    /// the MacCloud road test surfaced as the real-world spelling of a fetch.
    static let fetchVerbs: Set<String> = [
        "fetch", "find", "existing", "lookup", "query"
    ]

    /// Boolean state properties that read as "already handled". Curated hard, and
    /// tightened by the M4 public-corpus sweep: `isCancelled` fired on
    /// `if Task.isCancelled { return }` (cooperative cancellation, not dedup) across
    /// penny-bot, and the lifecycle flags (`isComplete`/`isDone`/`isFinished`/
    /// `isClosed`/`isExpired`) are ambiguous enough to drop. What remains is the set
    /// that genuinely reads "this key was already handled".
    static let stateFlags: Set<String> = [
        "isDeleted", "isHandled", "isProcessed", "isDismissed", "isArchived",
        "isRevoked", "isAcknowledged", "alreadyHandled", "handled", "processed"
    ]

    /// Callee base names that perform an observable **effect** — the thing a dedup
    /// gate exists to run at most once. M4 requires one: without it, a
    /// fetch-then-`return` or a flag-guard is a **getter**, not a handler, and the
    /// M3 sweep found the corpus full of those (`getReblogStatus`,
    /// `getRegisteredExternalUser`) firing as false positives.
    static let effectVerbs: Set<String> = [
        "insert", "save", "create", "delete", "remove", "update", "upsert",
        "post", "send", "publish", "write", "store", "persist", "commit",
        "enqueue", "dispatch", "emit", "put", "patch", "markAsDeleted",
        "markAsHandled", "markHandled", "destroy"
    ]

    /// The first dedup gate among the body's top-level statements, or `nil`.
    ///
    /// M4: requires the body to also perform an effect. A gate that guards nothing
    /// is a getter's early return, not a dedup gate — the distinction the sweep
    /// forced. Effect-dominance (the effect sits on the path the gate skips) is a
    /// finer check left to a later slice; "the body has an effect at all" removes
    /// the getter false positives without it.
    public static func classify(body: CodeBlockSyntax) -> DedupGateShape? {
        let fetchedNames = fetchBoundNames(in: body)
        for item in body.statements {
            guard let ifExpr = ifExpr(from: item), blockReturns(ifExpr.body) else {
                continue
            }
            if let shape = shape(of: ifExpr, fetchedNames: fetchedNames) {
                // Pay the whole-body effect walk only once a gate shape is found —
                // the ~99% of async/throws functions with no gate never trigger it.
                // A gate that guards no effect is a getter's early return, not dedup.
                return bodyHasEffect(body) ? shape : nil
            }
        }
        return nil
    }

    /// Whether the body performs at least one effect-verb call — the mutation a
    /// dedup gate is there to run once. Counts effects anywhere in the body,
    /// including inside a `db.transaction { … save … }` closure, since that is
    /// still the handler's effect.
    private static func bodyHasEffect(_ body: CodeBlockSyntax) -> Bool {
        firstCall(in: Syntax(body), matching: effectVerbs) != nil
    }

    /// Names bound to a fetch-verb call in a `let`/`var` statement, so a later
    /// `if let latest, latest.hash == … { return }` gate that re-binds an
    /// already-fetched value is recognised as fetch-then-insert too — the
    /// content-addressed, pre-fetched form the MacCloud road test surfaced.
    private static func fetchBoundNames(in body: CodeBlockSyntax) -> Set<String> {
        var names: Set<String> = []
        for item in body.statements {
            guard case let .decl(declaration) = item.item,
                  let variable = declaration.as(VariableDeclSyntax.self) else {
                continue
            }
            for binding in variable.bindings {
                guard let value = binding.initializer?.value,
                      firstCall(in: Syntax(value), matching: fetchVerbs) != nil,
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                else {
                    continue
                }
                names.insert(name)
            }
        }
        return names
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

    private static func shape(
        of ifExpr: IfExprSyntax,
        fetchedNames: Set<String>
    ) -> DedupGateShape? {
        for element in ifExpr.conditions {
            switch element.condition {
            case let .expression(expr):
                // `if dedup.hasHandled(orderID: order.id) { return false }`
                if let call = firstCall(in: Syntax(expr), matching: dedupVerbs) {
                    return .earlyReturnDedup(keyRoot: keyRoot(of: call))
                }
                // `if file.isDeleted { return .ok }` — state-flag gate (M3).
                if let flag = stateFlag(in: expr) {
                    return .stateFlagGuard(flag: flag)
                }

            case let .optionalBinding(binding):
                // Inline: `if let existing = context.fetch(descriptor) { return existing }`.
                if let value = binding.initializer?.value,
                   firstCall(in: Syntax(value), matching: fetchVerbs) != nil {
                    return .fetchThenInsert
                }
                // Pre-fetched: `if let latest, latest.hash == … { return }`, where
                // `latest` was bound to a fetch in an upstream statement (M3).
                if let source = bindingSourceName(binding), fetchedNames.contains(source) {
                    return .fetchThenInsert
                }

            default:
                continue
            }
        }
        return nil
    }

    /// The state-flag property this condition reads, if it is one — `isDeleted`
    /// from `file.isDeleted` (or a bare `isDeleted`). `nil` for anything not in
    /// the curated `stateFlags` set.
    private static func stateFlag(in expr: ExprSyntax) -> String? {
        let name: String?
        if let member = expr.as(MemberAccessExprSyntax.self) {
            name = member.declName.baseName.text
        } else {
            name = expr.as(DeclReferenceExprSyntax.self)?.baseName.text
        }
        guard let name, stateFlags.contains(name) else { return nil }
        return name
    }

    /// The value an optional binding rebinds: the initializer's root identifier
    /// (`if let x = latest`), or the bound name itself for the shorthand
    /// (`if let latest`). Used to tie a gate back to an upstream fetch.
    private static func bindingSourceName(_ binding: OptionalBindingConditionSyntax) -> String? {
        if let value = binding.initializer?.value {
            return rootIdentifier(of: value)
        }
        return binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
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
