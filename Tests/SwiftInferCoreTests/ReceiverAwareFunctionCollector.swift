import Foundation
import SwiftSyntax

// The syntax walkers for `BlindSpotBaseRateCensusMeasuredTests`. Split out for the
// 400-line file cap; the reasoning that governs them lives in that suite's header.
// Internal rather than private because the suite's controls address them directly — a
// walker that never fires and an empty corpus produce the same zero, and only a
// synthetic witness separates those readings.

/// Function declarations paired with **what `self` is** where they are declared.
///
/// The receiver's kind is the whole question in bucket 1: a write to `self` on a
/// `class` mutates state every holder of the reference sees, while on a `struct` it
/// mutates a copy and Swift makes the caller write `mutating`. An `extension` of a
/// type declared in another file cannot be resolved by a parse, so it gets its own
/// bucket instead of a guess — the same treatment the unrecognised-callee census gives
/// a callee it has no oracle for.
final class ReceiverAwareFunctionCollector: SyntaxVisitor {

    struct Entry {
        let function: FunctionDeclSyntax
        let kind: BlindSpotBaseRateCensusMeasuredTests.ReceiverKind
    }

    private(set) var entries: [Entry] = []
    private var stack: [BlindSpotBaseRateCensusMeasuredTests.ReceiverKind] = []
    /// Type names declared in this file, so an `extension` of a local type resolves
    /// rather than falling into `.unknown`.
    private var localKinds: [String: BlindSpotBaseRateCensusMeasuredTests.ReceiverKind] = [:]
    private var functionDepth = 0

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Nested functions belong to their enclosing function, not to the type.
        if functionDepth == 0, node.body != nil, let kind = stack.last {
            entries.append(Entry(function: node, kind: kind))
        }
        functionDepth += 1
        return .visitChildren
    }

    override func visitPost(_: FunctionDeclSyntax) { functionDepth -= 1 }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        localKinds[node.name.text] = .reference
        stack.append(.reference)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        localKinds[node.name.text] = .value
        stack.append(.value)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        localKinds[node.name.text] = .value
        stack.append(.value)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        localKinds[node.name.text] = .actorIsolated
        stack.append(.actorIsolated)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extended = node.extendedType.trimmedDescription
        stack.append(localKinds[extended] ?? .unknown)
        return .visitChildren
    }

    override func visitPost(_: ClassDeclSyntax) { stack.removeLast() }
    override func visitPost(_: StructDeclSyntax) { stack.removeLast() }
    override func visitPost(_: EnumDeclSyntax) { stack.removeLast() }
    override func visitPost(_: ActorDeclSyntax) { stack.removeLast() }
    override func visitPost(_: ExtensionDeclSyntax) { stack.removeLast() }
}

/// Whether a body assigns to `self.something`.
///
/// **Both operator forms**, because `Parser.parse` produces the unfolded one and a
/// visitor that knows only `InfixOperatorExprSyntax` sees no assignments at all —
/// the trap `ModuleStateCensusMeasuredTests` published a zero from before it was
/// caught, and which `PurityInferrer` documents one file away.
///
/// Closures are skipped: a closure mutating a capture is already refuted by
/// `refuteIfCaptured`, so counting it here would attribute a covered case to an
/// uncovered one.
final class SelfWriteChecker: SyntaxVisitor {

    private(set) var writesSelf = false

    override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if Self.isAssignment(Syntax(node.operator)) { note(node.leftOperand) }
        return .visitChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        for (index, element) in elements.enumerated() where index > 0 && Self.isAssignment(Syntax(element)) {
            note(elements[index - 1])
        }
        return .visitChildren
    }

    /// `=` and the compound forms, but not a comparison — `==` ends in `=` too.
    static func isAssignment(_ node: Syntax) -> Bool {
        if node.is(AssignmentExprSyntax.self) { return true }
        guard let binary = node.as(BinaryOperatorExprSyntax.self) else { return false }
        let text = binary.operator.text
        return text.hasSuffix("=") && !["==", "!=", "<=", ">=", "==="].contains(text)
    }

    /// An explicit `self.` receiver only. A bare `stored = value` also writes instance
    /// state, but bare names are ambiguous against locals without scope resolution, so
    /// counting them would inflate the bucket — this is a **lower bound**, stated in
    /// the census header.
    private func note(_ expression: ExprSyntax) {
        guard let member = expression.as(MemberAccessExprSyntax.self) else { return }
        if member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self) {
            writesSelf = true
        }
    }
}

/// Property names in a file declared with an explicitly **unordered** type — `Set<…>`
/// or a dictionary. Only annotated declarations: an inferred type is invisible to a
/// parse, which is one of the two reasons bucket 2 is a lower bound.
final class UnorderedPropertyCollector: SyntaxVisitor {

    private(set) var names: Set<String> = []

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let annotation = binding.typeAnnotation?.type.trimmedDescription else { continue }
            if Self.isUnordered(annotation) { names.insert(pattern.identifier.text) }
        }
        return .visitChildren
    }

    /// `Set<…>` and `[Key: Value]`. An array literal type `[Element]` is ordered and
    /// must not match, which is why this looks for the `:` rather than the brackets.
    static func isUnordered(_ type: String) -> Bool {
        if type.hasPrefix("Set<") { return true }
        guard type.hasPrefix("["), type.hasSuffix("]") else { return false }
        return type.contains(":")
    }
}

/// Renderings of an unordered property into a value the function returns — `joined`,
/// string interpolation, or `map` feeding either.
///
/// This is the shape SwiftLint fixed twice (`006bb2a8`, `0c095204`): a `Set` whose
/// iteration order reached a returned `String`. It cannot distinguish a rendering that
/// escapes from one that is immediately sorted, so a body containing `.sorted()` on the
/// same name is excluded — the fix's own shape must not count as the bug.
final class UnorderedRenderChecker: SyntaxVisitor {

    private let unordered: Set<String>
    private(set) var rendered: [String] = []
    private var sorted: Set<String> = []
    private var touched: Set<String> = []

    init(unordered: Set<String>, viewMode: SyntaxTreeViewMode) {
        self.unordered = unordered
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return .visitChildren
        }
        let method = member.declName.baseName.text
        guard let root = Self.rootName(of: member), unordered.contains(root) else {
            return .visitChildren
        }
        if method == "sorted" { sorted.insert(root) }
        if ["joined", "map"].contains(method) { touched.insert(root) }
        return .visitChildren
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        for segment in node.segments {
            guard let expression = segment.as(ExpressionSegmentSyntax.self) else { continue }
            for element in expression.expressions {
                if let name = element.expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
                   unordered.contains(name) {
                    touched.insert(name)
                }
            }
        }
        return .visitChildren
    }

    override func visitPost(_: SourceFileSyntax) { finish() }
    override func visitPost(_: CodeBlockSyntax) { finish() }

    private func finish() {
        rendered = touched.subtracting(sorted).sorted()
    }

    /// The name a member chain rests on: `kinds.map { … }.joined()` roots at `kinds`.
    static func rootName(of expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) { return reference.baseName.text }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base {
            return rootName(of: base)
        }
        if let call = expression.as(FunctionCallExprSyntax.self) { return rootName(of: call.calledExpression) }
        return nil
    }

    static func rootName(of member: MemberAccessExprSyntax) -> String? {
        member.base.flatMap { rootName(of: $0) }
    }
}
