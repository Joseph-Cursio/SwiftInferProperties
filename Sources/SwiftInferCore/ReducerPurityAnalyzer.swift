import Foundation
import SwiftParser
import SwiftSyntax

/// V2.0 M3.A — classifies a reducer body's "purity" for verify-path
/// routing. Walks the body's expression / statement tree once via
/// SwiftSyntax and emits one of three labels:
///
///   - `.pure` — no effect / async / Task references found. Safe for
///     the in-process verify path (PRD v2.0 §7.2).
///   - `.effectBearing` — body references `Effect` / `Task` /
///     `AnyCancellable`, awaits an async call, or invokes a known
///     effect API (`.run` / `.send` / `.cancel` / `.fireAndForget`).
///     Routes to the subprocess verify path (PRD §7.3, §5.8 M8).
///   - `.hiddenMutability` — body writes to a static / global var.
///     `-∞` veto in PRD §4.1; the reducer is non-deterministic in
///     both verify paths so the suggestion is suppressed.
///
/// **Heuristic, not type-resolution.** Detection is textual /
/// name-based. False positives (a user-defined `Effect` type that
/// isn't TCA's) cause subprocess routing — slower but not incorrect.
/// False negatives (a side-effect via `print`, file I/O, etc. that
/// isn't routed here) result in the in-process path running real
/// side effects in swift-infer's host process. PRD §16 #1a documents
/// that this is the intended trade-off — the alternative (full type
/// resolution) is significantly heavier and v1 routinely accepts
/// the same shape of conservative-textual approximation.
///
/// **Why not just check `effectBearing`?** A reducer with hidden
/// mutability (writes to `Self.staticCounter += 1`) still produces
/// the wrong outcomes in *both* verify paths — every action sequence
/// reads a state that shifted under it. PRD §4.1 vetoes these with
/// `-∞`. Worth distinguishing from `.effectBearing` (which is just a
/// routing signal) so the caller can suppress rather than route.
public enum ReducerPurityAnalyzer {

    /// Walk the function body and emit a purity label. Pure /
    /// `nil`-body case (protocol requirements, externs) returns
    /// `.pure` — no body means no detectable impurity.
    public static func analyze(_ function: FunctionDeclSyntax) -> ReducerPurity {
        guard let body = function.body else { return .pure }
        return analyze(Syntax(body))
    }

    /// Walk any syntax subtree (used by M3 when feeding in a TCA
    /// `Reduce { state, action in ... }` closure rather than a
    /// function decl).
    public static func analyze(_ subtree: Syntax) -> ReducerPurity {
        let visitor = Visitor()
        visitor.walk(subtree)
        if visitor.foundHiddenMutability { return .hiddenMutability }
        if visitor.foundEffectSignal { return .effectBearing }
        return .pure
    }
}

/// V2.0 M3.A — three-state purity classification. Stable rawValues
/// so downstream consumers (M3 verify routing, M4+ scoring) can key
/// on them.
public enum ReducerPurity: String, Sendable, Equatable, Codable, CaseIterable {
    case pure
    case effectBearing = "effect-bearing"
    case hiddenMutability = "hidden-mutability"
}

private final class Visitor: SyntaxVisitor {

    var foundEffectSignal = false
    var foundHiddenMutability = false

    /// Identifier names that strongly indicate effect-bearing code.
    /// Conservative — we'd rather route to subprocess (slow but
    /// correct) than run effect code in-process.
    private static let effectTypeNames: Set<String> = [
        "Effect",
        "EffectOf",
        "EffectTask",
        "Task",
        "AnyCancellable"
    ]

    /// Method-call name suffixes (`<expr>.<name>(...)`) that route a
    /// reducer to the subprocess path. Matches TCA's effect-construction
    /// surface and the common Swift Concurrency entries.
    private static let effectMethodNames: Set<String> = [
        "run",
        "send",
        "cancel",
        "fireAndForget"
    ]

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - async / await

    override func visit(_: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
        foundEffectSignal = true
        return .skipChildren
    }

    // MARK: - Type-reference effect signals

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if Self.effectTypeNames.contains(node.baseName.text) {
            foundEffectSignal = true
        }
        return .visitChildren
    }

    /// Type annotations like `let token: AnyCancellable?` or
    /// `Task<Void, Never>` surface as `IdentifierTypeSyntax`, not
    /// `DeclReferenceExprSyntax`. Cover that path too.
    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        if Self.effectTypeNames.contains(node.name.text) {
            foundEffectSignal = true
        }
        return .visitChildren
    }

    // MARK: - Method-call effect signals + static-var writes

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
           Self.effectMethodNames.contains(member.declName.baseName.text) {
            // Methods like `.run`, `.send`, `.cancel`, `.fireAndForget`
            // on any base — Effect.run, store.send, task.cancel, etc.
            // Conservative: route to subprocess.
            foundEffectSignal = true
        }
        return .visitChildren
    }

    // MARK: - Hidden mutability — static / Self assignments

    /// Catches `Self.foo = ...`, `Self.foo += ...`, or
    /// `<TypeName>.foo = ...` — non-deterministic in either verify
    /// path because the static state persists across action-sequence
    /// runs. Local `state.foo = ...` is fine (it's the reducer's
    /// `inout` target). Recognized operators: `=`, `+=`, `-=`, `*=`,
    /// `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`.
    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        guard Self.isAssignmentOperator(node.operator) else { return .visitChildren }
        if isStaticOrSelfMemberAccess(node.leftOperand) {
            foundHiddenMutability = true
        }
        return .visitChildren
    }

    /// SwiftParser leaves operator sequences unfolded — `Self.counter
    /// += 1` parses as a SequenceExprSyntax of `[Self.counter, +=, 1]`,
    /// NOT as an InfixOperatorExprSyntax (the latter requires operator-
    /// precedence folding that SwiftSyntax doesn't perform).
    /// `BodySignalVisitor` and friends in v1 hit the same edge — every
    /// SyntaxVisitor that wants to detect compound assignments has to
    /// walk the sequence form too.
    ///
    /// We look for the pattern `<staticBase>.<member> <op> <rhs>` where
    /// `<op>` is any assignment-shaped operator. Two-element pairs
    /// (`Self.foo = bar`) and three-element triplets (the common form)
    /// both work — the assignment operator is always at index 1 and
    /// the LHS is at index 0.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.elements.count >= 3 else { return .visitChildren }
        let elements = Array(node.elements)
        // Look for any `<lhs> <op> <rhs>` substring where `<op>` is an
        // assignment-shaped operator.
        for index in 1..<elements.count - 1 {
            let candidate = elements[index]
            if Self.isAssignmentOperator(candidate),
               isStaticOrSelfMemberAccess(elements[index - 1]) {
                foundHiddenMutability = true
                break
            }
        }
        return .visitChildren
    }

    /// `SomeType.<name>` or `Self.<name>` — distinct from a local
    /// `state.<name>` (where `state` is a normal identifier lowercased
    /// by convention). The heuristic is name-shape: uppercase first
    /// letter on the leftmost base, OR the base is literally `Self`.
    private func isStaticOrSelfMemberAccess(_ expression: ExprSyntax) -> Bool {
        guard let member = expression.as(MemberAccessExprSyntax.self) else { return false }
        guard let base = member.base else { return false }
        if let ref = base.as(DeclReferenceExprSyntax.self) {
            let baseName = ref.baseName.text
            if baseName == "Self" { return true }
            // First-letter-uppercase: likely a type name (Swift convention).
            return baseName.first?.isUppercase == true
        }
        // Nested member access — walk deeper.
        return isStaticOrSelfMemberAccess(ExprSyntax(base))
    }

    /// Plain `=` is encoded as `AssignmentExprSyntax`; compound
    /// assignments (`+=`, `-=`, etc.) are `BinaryOperatorExprSyntax`
    /// whose operator text ends with `=` but isn't `==` / `!=` /
    /// `<=` / `>=`. Centralizing the recognition here so the
    /// hidden-mutability rule covers all compound forms.
    private static func isAssignmentOperator(_ expression: ExprSyntax) -> Bool {
        if expression.is(AssignmentExprSyntax.self) { return true }
        guard let binary = expression.as(BinaryOperatorExprSyntax.self) else { return false }
        let text = binary.operator.text
        // Comparison operators end in `=` but are not assignments.
        if text == "==" || text == "!=" || text == "<=" || text == ">=" {
            return false
        }
        return text.hasSuffix("=")
    }
}
