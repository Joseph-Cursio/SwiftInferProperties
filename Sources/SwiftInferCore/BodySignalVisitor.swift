import SwiftSyntax

/// Walks a single function body and collects the M1.2 + M2.4 + M2.5
/// signals: non-deterministic API calls, self-composition shapes, and
/// reducer-op references (with the M2.5 identity-shaped seed
/// classification on top).
final class BodySignalVisitor: SyntaxVisitor {

    let funcName: String
    var detectedAPIs: Set<String> = []
    var foundSelfComposition = false
    var reducerOps: Set<String> = []
    var reducerOpsWithIdentitySeed: Set<String> = []

    init(funcName: String) {
        self.funcName = funcName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let calleeText = node.calledExpression.trimmedDescription
        if NonDeterministicAPIs.matches(calleeText) {
            detectedAPIs.insert(calleeText)
        }
        if calleeText == funcName {
            for arg in node.arguments
            where arg.expression.as(FunctionCallExprSyntax.self)?
                .calledExpression
                .trimmedDescription == funcName {
                foundSelfComposition = true
            }
        }
        recordReducerOp(in: node)
        return .visitChildren
    }

    /// Detect `<expr>.reduce(<seed>, <op>)` and `<expr>.reduce(into: <seed>, <op>)`
    /// where `<op>` is a function reference (bare identifier or member-access
    /// `Type.method`). Trailing closures and explicit closure literals are
    /// intentionally skipped — the M2.4 detector only resolves named-function
    /// references, mirroring the conservative-precision posture of §3.5.
    /// M2.5 extends this to additionally classify whether the `<seed>`
    /// argument is identity-shaped (literal zero / empty collection / nil /
    /// false, or a member-access leaf in the curated identity-name list);
    /// that classification feeds the identity-element template's
    /// accumulator-with-empty-seed signal (PRD §5.3, +20).
    private func recordReducerOp(in node: FunctionCallExprSyntax) {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "reduce",
              node.arguments.count == 2 else {
            return
        }
        let seedArg = node.arguments[node.arguments.startIndex]
        let opArg = node.arguments[node.arguments.index(node.arguments.startIndex, offsetBy: 1)]
        let opName: String?
        if let ref = opArg.expression.as(DeclReferenceExprSyntax.self) {
            opName = ref.baseName.text
        } else if let memberRef = opArg.expression.as(MemberAccessExprSyntax.self) {
            opName = memberRef.declName.baseName.text
        } else {
            opName = nil
        }
        guard let opName else {
            return
        }
        reducerOps.insert(opName)
        if isIdentityShapedSeed(seedArg.expression) {
            reducerOpsWithIdentitySeed.insert(opName)
        }
    }

    private func isIdentityShapedSeed(_ expression: ExprSyntax) -> Bool {
        if isIdentityShapedLiteral(expression) {
            return true
        }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            return IdentityNames.curated.contains(memberAccess.declName.baseName.text)
        }
        return false
    }

    private func isIdentityShapedLiteral(_ expression: ExprSyntax) -> Bool {
        if let int = expression.as(IntegerLiteralExprSyntax.self) {
            return int.literal.text == "0"
        }
        if let float = expression.as(FloatLiteralExprSyntax.self) {
            return float.literal.text == "0.0"
        }
        if let str = expression.as(StringLiteralExprSyntax.self) {
            return isEmptyStringLiteral(str)
        }
        if let array = expression.as(ArrayExprSyntax.self) {
            return array.elements.isEmpty
        }
        if let dict = expression.as(DictionaryExprSyntax.self) {
            return isEmptyDictionaryLiteral(dict)
        }
        if expression.is(NilLiteralExprSyntax.self) {
            return true
        }
        if let bool = expression.as(BooleanLiteralExprSyntax.self) {
            return bool.literal.text == "false"
        }
        return false
    }

    private func isEmptyStringLiteral(_ str: StringLiteralExprSyntax) -> Bool {
        str.segments.allSatisfy { segment in
            guard let plain = segment.as(StringSegmentSyntax.self) else {
                return false
            }
            return plain.content.text.isEmpty
        }
    }

    private func isEmptyDictionaryLiteral(_ dict: DictionaryExprSyntax) -> Bool {
        switch dict.content {
        case .colon:
            return true
        case .elements(let elements):
            return elements.isEmpty
        }
    }
}

/// Curated callee-text matches for non-deterministic APIs. Kept small
/// and explicit for M1.2; expansion happens as templates encounter
/// false negatives.
private enum NonDeterministicAPIs {

    private static let exactMatches: Set<String> = [
        "Date",
        "Date.now",
        "UUID",
        "URLSession.shared",
        "arc4random",
        "arc4random_uniform",
        "drand48",
        "rand",
        "random"
    ]

    /// Callee texts ending in `.random` or `.random(in:)` cover the
    /// `Int.random`, `Double.random(in:)`, `Bool.random()` family
    /// without enumerating every numeric type.
    private static let suffixMatches: [String] = [
        ".random",
        ".random(in:)"
    ]

    static func matches(_ calleeText: String) -> Bool {
        if exactMatches.contains(calleeText) {
            return true
        }
        return suffixMatches.contains { calleeText.hasSuffix($0) }
    }
}
