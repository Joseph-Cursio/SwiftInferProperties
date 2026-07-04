import Foundation
import SwiftSyntax

/// V1.B — recursive walker over a `var body` subtree that emits one
/// `ReducerCandidate` per `Reduce { state, action in ... }` call with
/// an arity-2 trailing closure. Pulled out of `ReducerDiscoverer.swift`
/// into its own file so the main discoverer stays under the
/// `file_length` cap as the V1.B TCA path landed.
///
/// **What it walks.** Arbitrary expressions — every descendant of the
/// passed-in subtree is visited, so `Reduce` calls inside `Scope` /
/// `CombineReducers` / `EmptyReducer` / `BindingReducer` wrappers are
/// found automatically (PRD §6.3: "When `body` composes multiple
/// `Reduce` closures via `CombineReducers`, each closure is detected
/// independently and surfaces as a separate reducer candidate").
///
/// **What it matches (V1.B + Finding I).** Two forms of `Reduce(...)`:
/// (1) the closure form `Reduce { state, action in ... }` (V1.B
/// original), and (2) the method-reference form `Reduce(<methodName>)`
/// where the conformer defines `reduce(into:action:)` (or similar) as
/// a separate method and passes it by reference. Finding I from
/// kitlangton/Hex dogfood (cycle-dogfood-hex) — common real-world
/// idiom when reducer bodies grow beyond a comfortable inline closure.
///
/// **What it ignores.** `Reduce` calls without either shape (e.g.
/// `Reduce { $0 }`, `Reduce(into: { ... }, action: { ... })`,
/// `Reduce(.someEnumCase)`) — not the canonical M1.B / Finding-I
/// shapes. The pre-1.0 TCA `Reduce(into:action:)` API can be added
/// at a later milestone if calibration shows it's common in OSS
/// corpora.
///
/// **Closure parameter names are not validated.** The convention is
/// `state, action` but `s, a` / `value, msg` / anything else are all
/// valid Swift; M1.B does not filter on names — vocabulary-based
/// filtering is a §4 scoring signal at M4+.
final class ReduceClosureWalker: SyntaxVisitor {

    var candidates: [ReducerCandidate] = []
    let file: String
    let converter: SourceLocationConverter
    let enclosingTypeName: String
    /// Cycle 122/125 — the Action enum's cases (name + payload types) for
    /// this reducer, stamped onto every emitted `.tca` candidate. Empty
    /// when no `Action` enum was found.
    let actionCases: [ActionCaseInfo]
    /// Item 2 slice 3 — the nested `State` struct's `id` type, stamped onto
    /// every emitted candidate so a parent can resolve this reducer's
    /// `State.ID` for an `IdentifiedActionOf<Self>` element. `nil` when the
    /// State declares no `id`.
    let stateIDTypeName: String?

    init(
        file: String,
        converter: SourceLocationConverter,
        enclosingTypeName: String,
        actionCases: [ActionCaseInfo] = [],
        stateIDTypeName: String? = nil
    ) {
        self.file = file
        self.converter = converter
        self.enclosingTypeName = enclosingTypeName
        self.actionCases = actionCases
        self.stateIDTypeName = stateIDTypeName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "Reduce" else {
            // Not a `Reduce(...)` call — keep walking; the closure may
            // be nested inside a `Scope { ... }` or similar wrapper.
            return .visitChildren
        }
        // Closure form: Reduce { state, action in ... }
        if let closure = node.trailingClosure,
           closureParameterCount(closure) == 2 {
            emitCandidate(closure: closure)
            return .visitChildren
        }
        // Finding-I method-reference form: Reduce(<identifier>). Single
        // unlabeled argument that's a bare DeclReferenceExpr (e.g.
        // `Reduce(reduce)`). Rejects: labeled arguments, .enumCase
        // sugar, member access (`self.handle`), closures.
        if node.trailingClosure == nil,
           node.arguments.count == 1,
           let arg = node.arguments.first,
           arg.label == nil,
           arg.expression.is(DeclReferenceExprSyntax.self) {
            emitCandidateForMethodRef(at: node)
        }
        return .visitChildren
    }

    /// Count parameters declared by a closure's signature. Handles
    /// both the shorthand form (`{ a, b in ... }`) and the typed form
    /// (`{ (a: A, b: B) in ... }`). Returns 0 when the closure has no
    /// signature at all — e.g. `Reduce { $0 }` (which isn't a
    /// reducer-shaped closure under M1.B's posture).
    private func closureParameterCount(_ closure: ClosureExprSyntax) -> Int {
        guard let signature = closure.signature else { return 0 }
        guard let parameterClause = signature.parameterClause else { return 0 }
        if let shorthand = parameterClause.as(ClosureShorthandParameterListSyntax.self) {
            return shorthand.count
        }
        if let typed = parameterClause.as(ClosureParameterClauseSyntax.self) {
            return typed.parameters.count
        }
        return 0
    }

    private func emitCandidate(closure: ClosureExprSyntax) {
        let position = closure.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        // M8.B — analyze the closure body for purity. TCA closures
        // are typically `.effectBearing` (they construct `Effect.run`
        // / `.send` etc.), but signature-pure closures qualify for the
        // pure path at the routing layer.
        let purity = ReducerPurityAnalyzer.analyze(Syntax(closure.statements))
        candidates.append(ReducerCandidate(
            location: "\(file):\(location.line)",
            enclosingTypeName: enclosingTypeName,
            functionName: "body",
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: "\(enclosingTypeName).State",
            actionTypeName: "\(enclosingTypeName).Action",
            carrierKind: .tca,
            purity: purity,
            actionCases: actionCases,
            stateIDTypeName: stateIDTypeName
        ))
    }

    /// Finding I — emit a candidate for `Reduce(<methodName>)`. Without
    /// resolving the referenced method's body we can't run the purity
    /// analyzer; default to `.effectBearing` (the dominant TCA pattern,
    /// safe routing — `.effectBearing` always uses the subprocess
    /// verify path which works for both pure and effect-bearing
    /// reducers).
    private func emitCandidateForMethodRef(at call: FunctionCallExprSyntax) {
        let position = call.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        candidates.append(ReducerCandidate(
            location: "\(file):\(location.line)",
            enclosingTypeName: enclosingTypeName,
            functionName: "body",
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: "\(enclosingTypeName).State",
            actionTypeName: "\(enclosingTypeName).Action",
            carrierKind: .tca,
            purity: .effectBearing,
            actionCases: actionCases,
            stateIDTypeName: stateIDTypeName
        ))
    }
}
