import Foundation
import SwiftInferCore
import SwiftSyntax

/// TestStore Trace Mining, Slice 1 — extracts the ordered action
/// sequences a repo's TCA `TestStore` tests already contain, so the
/// interaction verifier can check developer-authored orderings before
/// (never instead of) random generation. See
/// `docs/teststore-trace-mining-build-plan.md`.
///
/// Consumes `TestMethodSummary.body` — the same input the `Slicer` takes,
/// so no new parsing infrastructure. Recognizes, per test body:
///   - `TestStore(initialState:) { Feature() }` (or a `reducer:` arg) →
///     the reducer type + verbatim initial-state expression;
///   - `store.send(.case(args))` / `store.receive(.case(args))` on a
///     bound `TestStore` variable → one `MinedAction` each.
///
/// **Argument capture is verbatim** — a payload-bearing action's args
/// reference test-body-local bindings, so they're recorded but not
/// reconstructible standalone (Slice 2 emits only the payload-free
/// subset; §3 of the build plan).
///
/// **Hard contract (PRD §15):** never throws from the per-summary path.
/// A body with no `TestStore` yields `[]`.
public enum TestStoreTraceExtractor {

    /// Mine every `TestStore` trace from one parsed test method.
    public static func extract(from summary: TestMethodSummary) -> [MinedActionTrace] {
        let visitor = TestStoreTraceVisitor(viewMode: .sourceAccurate)
        visitor.walk(summary.body)
        return assembleTraces(
            constructions: visitor.constructions,
            actions: visitor.actions,
            location: summary.location
        )
    }

    /// Mine traces from every test method under `directory`. Reuses
    /// `TestSuiteParser`'s deterministic sorted-path scan.
    public static func extract(fromTestsDirectory directory: URL) throws -> [MinedActionTrace] {
        let summaries = try TestSuiteParser.scanTests(directory: directory)
        return summaries.flatMap { extract(from: $0) }
    }

    // MARK: - Trace assembly

    /// Group the flat construction / action event lists (each carrying a
    /// source-order index) into one trace per `TestStore`.
    private static func assembleTraces(
        constructions: [RawConstruction],
        actions: [RawAction],
        location: SwiftInferCore.SourceLocation
    ) -> [MinedActionTrace] {
        // Fallback: sends on the conventional bare `store` name with no
        // resolved construction (e.g. built in a helper). Restricted to
        // `store` so an unrelated `foo.send(x)` is never mined.
        guard !constructions.isEmpty else {
            let storeActions = actions.filter { $0.receiverName == "store" }
            guard !storeActions.isEmpty else {
                return []
            }
            let fallback = makeTrace(
                reducerTypeName: nil,
                initialStateExpr: nil,
                actions: storeActions,
                location: location
            )
            return [fallback]
        }

        var traces: [MinedActionTrace] = []
        for (index, construction) in constructions.enumerated() {
            guard let varName = construction.varName else {
                continue  // unbound TestStore can't be referenced by a named send
            }
            // Actions for this var after its construction, up to the next
            // re-construction of the same var (rare) — keeps separate
            // stores separate.
            let nextSameVarOrder = constructions[(index + 1)...]
                .first { $0.varName == varName }?.order ?? Int.max
            let mine = actions.filter {
                $0.receiverName == varName
                    && $0.order > construction.order
                    && $0.order < nextSameVarOrder
            }
            guard !mine.isEmpty else {
                continue  // an actionless store isn't useful for action mining
            }
            traces.append(makeTrace(
                reducerTypeName: construction.reducerTypeName,
                initialStateExpr: construction.initialStateExpr,
                actions: mine,
                location: location
            ))
        }
        return traces
    }

    private static func makeTrace(
        reducerTypeName: String?,
        initialStateExpr: String?,
        actions: [RawAction],
        location: SwiftInferCore.SourceLocation
    ) -> MinedActionTrace {
        // `actions` arrive in source order already (visitor is pre-order).
        MinedActionTrace(
            reducerTypeName: reducerTypeName,
            initialStateExpr: initialStateExpr,
            sent: actions.filter { $0.action.kind == .send }.map(\.action),
            received: actions.filter { $0.action.kind == .receive }.map(\.action),
            location: location
        )
    }
}

// MARK: - Raw events

/// A `TestStore(...)` construction, tagged with its bound variable name
/// (`nil` if inline/unbound) and source-order index.
struct RawConstruction {
    let varName: String?
    let reducerTypeName: String?
    let initialStateExpr: String?
    let order: Int
}

/// One `send` / `receive` call, tagged with its receiver variable name
/// and source-order index.
struct RawAction {
    let receiverName: String
    let action: MinedAction
    let order: Int
}

// MARK: - Visitor

/// Single-pass walker collecting construction + send/receive events in
/// source order (pre-order DFS visits siblings in source order, so a
/// monotonic counter records relative order).
final class TestStoreTraceVisitor: SyntaxVisitor {

    var constructions: [RawConstruction] = []
    var actions: [RawAction] = []
    private var orderCounter = 0

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if node.calledExpression.trailingIdentifierName == "TestStore" {
            recordConstruction(node)
            return .visitChildren
        }
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
           let base = member.base?.as(DeclReferenceExprSyntax.self),
           let kind = sendReceiveKind(member.declName.baseName.text),
           let action = minedAction(kind: kind, from: node.arguments.first?.expression) {
            actions.append(RawAction(
                receiverName: base.baseName.text,
                action: action,
                order: nextOrder()
            ))
        }
        return .visitChildren
    }

    // MARK: - Construction

    private func recordConstruction(_ node: FunctionCallExprSyntax) {
        let reducerName = reducerExpression(in: node).flatMap(reducerTypeName(from:))
        let initialState = node.arguments
            .first { $0.label?.text == "initialState" }?
            .expression.trimmedDescription
        constructions.append(RawConstruction(
            varName: boundVariableName(of: node),
            reducerTypeName: reducerName,
            initialStateExpr: initialState,
            order: nextOrder()
        ))
    }

    /// The reducer expression — the trailing closure's last expression
    /// (`{ Feature() }`) or an explicit `reducer:` argument.
    private func reducerExpression(in node: FunctionCallExprSyntax) -> ExprSyntax? {
        if let closure = node.trailingClosure {
            for item in closure.statements.reversed() {
                if case .expr(let expr) = item.item {
                    return expr
                }
            }
        }
        return node.arguments.first { $0.label?.text == "reducer" }?.expression
    }

    /// Descend a reducer expression to the constructed type name:
    /// `Feature()` → `"Feature"`, `Feature()._printChanges()` →
    /// `"Feature"`.
    private func reducerTypeName(from expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let call = expr.as(FunctionCallExprSyntax.self) {
            return reducerTypeName(from: call.calledExpression)
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            if let base = member.base {
                return reducerTypeName(from: base)
            }
            return member.declName.baseName.text
        }
        return nil
    }

    /// Walk ancestors to the `let store = ...` binding name; `nil` if the
    /// construction isn't bound to a simple identifier pattern.
    private func boundVariableName(of node: some SyntaxProtocol) -> String? {
        var current = node.parent
        while let ancestor = current {
            if let binding = ancestor.as(PatternBindingSyntax.self) {
                return binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            }
            if ancestor.is(CodeBlockItemSyntax.self) {
                return nil  // reached the statement boundary without a binding
            }
            current = ancestor.parent
        }
        return nil
    }

    // MARK: - Action classification

    private func sendReceiveKind(_ name: String) -> MinedAction.Kind? {
        switch name {
        case "send": return .send
        case "receive": return .receive
        default: return nil
        }
    }

    /// Classify a `send` / `receive` first argument into a `MinedAction`.
    /// `.dismiss` → payload-free; `.select(a.id)` → payload-bearing with
    /// verbatim arg text. Anything else (a bare variable, a key path) is
    /// not a recognizable action literal → `nil` (skipped for precision).
    private func minedAction(kind: MinedAction.Kind, from argument: ExprSyntax?) -> MinedAction? {
        guard let argument else {
            return nil
        }
        if let member = argument.as(MemberAccessExprSyntax.self) {
            return MinedAction(kind: kind, caseName: member.declName.baseName.text, argumentTexts: [])
        }
        if let call = argument.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return MinedAction(
                kind: kind,
                caseName: member.declName.baseName.text,
                argumentTexts: call.arguments.map(\.expression.trimmedDescription)
            )
        }
        return nil
    }

    private func nextOrder() -> Int {
        defer { orderCounter += 1 }
        return orderCounter
    }
}
