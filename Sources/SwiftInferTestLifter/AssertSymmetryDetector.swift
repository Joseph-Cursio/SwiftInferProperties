import SwiftInferCore
import SwiftSyntax

/// PRD §7.3 "Assert-Symmetry → commutativity" detector. Runs against
/// the **property region** of a sliced test (not the raw body),
/// mirroring `AssertAfterTransformDetector` and
/// `AssertAfterDoubleApplyDetector`'s shape.
///
/// **Recognized shapes:**
/// - **Explicit** (three lines):
///   ```
///   let lhs = merge(a, b)
///   let rhs = merge(b, a)
///   XCTAssertEqual(lhs, rhs)
///   ```
/// - **Collapsed** (one assertion line):
///   ```
///   XCTAssertEqual(merge(a, b), merge(b, a))
///   #expect(union(s1, s2) == union(s2, s1))
///   ```
///
/// **Invariants** — all three required for detection:
/// - **Single-callee**: both call sites must reference the same `f`.
///   Different callees (`f(a, b) == g(b, a)`) aren't a commutativity
///   claim, they're an unrelated equality.
/// - **Distinct-argument**: the two argument identifier names must
///   differ (`a != b` by name). `f(a, a) == f(a, a)` is a tautology
///   carrying no commutativity evidence and must not detect.
/// - **Argument-reversed**: the second call's argument identifiers must
///   be the reverse of the first's. `f(a, b) == f(a, b)` (no reversal)
///   isn't symmetry evidence either.
///
/// **Out of scope for M2.2:** `#expect(lhs == rhs)` explicit form
/// (mirrors M1.3 / M2.1's posture — explicit form supports
/// `XCTAssertEqual` only); three-or-more-argument permutations
/// (matches `CommutativityTemplate`'s two-parameter shape per the M2
/// plan's open decision #6); receivers swapping mid-chain.
public enum AssertSymmetryDetector {

    public static func detect(in slice: SlicedTestBody) -> [DetectedCommutativity] {
        guard let assertion = slice.assertion else {
            return []
        }
        if let collapsed = detectCollapsed(assertion: assertion) {
            return [collapsed]
        }
        if let explicit = detectExplicit(assertion: assertion, propertyRegion: slice.propertyRegion) {
            return [explicit]
        }
        return []
    }

    // MARK: - Collapsed shape

    /// `XCTAssertEqual(f(a, b), f(b, a))` /
    /// `#expect(f(a, b) == f(b, a))` — one assertion-line shape.
    private static func detectCollapsed(assertion: AssertionInvocation) -> DetectedCommutativity? {
        switch assertion.kind {
        case .xctAssertEqual:
            return collapsedFromTwoArguments(
                lhs: assertion.arguments.first,
                rhs: assertion.arguments.dropFirst().first,
                location: assertion.location
            )
        case .expectMacro:
            guard let firstArg = assertion.arguments.first else {
                return nil
            }
            return collapsedFromEqualityExpression(firstArg, location: assertion.location)
        case .xctAssertTrue, .xctAssert, .xctAssertNotNil, .requireMacro:
            return nil
        }
    }

    private static func collapsedFromTwoArguments(
        lhs: ExprSyntax?,
        rhs: ExprSyntax?,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedCommutativity? {
        guard let lhs, let rhs,
              let lhsCall = lhs.as(FunctionCallExprSyntax.self),
              let rhsCall = rhs.as(FunctionCallExprSyntax.self) else {
            return nil
        }
        return commutativityFromCalls(lhs: lhsCall, rhs: rhsCall, location: location)
    }

    private static func collapsedFromEqualityExpression(
        _ expr: ExprSyntax,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedCommutativity? {
        if let sequence = expr.as(SequenceExprSyntax.self) {
            return collapsedFromSequence(sequence, location: location)
        }
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           let opExpr = infix.operator.as(BinaryOperatorExprSyntax.self),
           opExpr.operator.text == "==" {
            return collapsedFromTwoArguments(
                lhs: infix.leftOperand,
                rhs: infix.rightOperand,
                location: location
            )
        }
        return nil
    }

    private static func collapsedFromSequence(
        _ sequence: SequenceExprSyntax,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedCommutativity? {
        let elements = Array(sequence.elements)
        guard elements.count == 3,
              let opExpr = elements[1].as(BinaryOperatorExprSyntax.self),
              opExpr.operator.text == "==" else {
            return nil
        }
        return collapsedFromTwoArguments(
            lhs: elements[0],
            rhs: elements[2],
            location: location
        )
    }

    // MARK: - Explicit shape

    /// `let lhs = f(a, b); let rhs = f(b, a); XCTAssertEqual(lhs, rhs)`
    /// — three-statement shape.
    private static func detectExplicit(
        assertion: AssertionInvocation,
        propertyRegion: [CodeBlockItemSyntax]
    ) -> DetectedCommutativity? {
        guard assertion.kind == .xctAssertEqual,
              assertion.arguments.count == 2,
              let lhsRef = assertion.arguments[0].as(DeclReferenceExprSyntax.self),
              let rhsRef = assertion.arguments[1].as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let bindings = collectBindings(in: propertyRegion)
        guard let lhsInit = bindings[lhsRef.baseName.text],
              let lhsCall = lhsInit.as(FunctionCallExprSyntax.self),
              let rhsInit = bindings[rhsRef.baseName.text],
              let rhsCall = rhsInit.as(FunctionCallExprSyntax.self) else {
            return nil
        }
        return commutativityFromCalls(lhs: lhsCall, rhs: rhsCall, location: assertion.location)
    }

    // MARK: - Shared call-pair check

    /// Apply the single-callee + distinct-argument + argument-reversed
    /// invariants to a pair of call expressions. Returns `nil` if any
    /// invariant fails. Both call sites must extract to the same shape
    /// (free / static `f(a, b)` OR method `a.f(b)`); see
    /// `extractCommutativityPair`.
    private static func commutativityFromCalls(
        lhs: FunctionCallExprSyntax,
        rhs: FunctionCallExprSyntax,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedCommutativity? {
        guard let lhsPair = extractCommutativityPair(from: lhs),
              let rhsPair = extractCommutativityPair(from: rhs),
              lhsPair.calleeName == rhsPair.calleeName,
              lhsPair.leftArgName != lhsPair.rightArgName,
              lhsPair.leftArgName == rhsPair.rightArgName,
              lhsPair.rightArgName == rhsPair.leftArgName else {
            return nil
        }
        return DetectedCommutativity(
            calleeName: lhsPair.calleeName,
            leftArgName: lhsPair.leftArgName,
            rightArgName: lhsPair.rightArgName,
            assertionLocation: location
        )
    }

    /// Extract `(calleeName, leftOperand, rightOperand)` from a call
    /// expression in one of two shapes: (i) free function or static
    /// method `f(a, b)` — two argument positions, both
    /// `DeclReferenceExpr`; (ii) instance method `a.f(b)` — receiver is
    /// `DeclReferenceExpr`, single argument is `DeclReferenceExpr`. The
    /// receiver-as-first-operand path lets `Set.union` style call sites
    /// (`a.union(b) == b.union(a)`) detect.
    private static func extractCommutativityPair(
        from call: FunctionCallExprSyntax
    ) -> CommutativityPair? {
        let args = Array(call.arguments)

        if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let base = member.base,
           let receiverRef = base.as(DeclReferenceExprSyntax.self),
           args.count == 1,
           let argRef = args[0].expression.as(DeclReferenceExprSyntax.self) {
            return CommutativityPair(
                calleeName: member.declName.baseName.text,
                leftArgName: receiverRef.baseName.text,
                rightArgName: argRef.baseName.text
            )
        }

        if args.count == 2,
           let leftRef = args[0].expression.as(DeclReferenceExprSyntax.self),
           let rightRef = args[1].expression.as(DeclReferenceExprSyntax.self),
           let name = calleeName(of: call.calledExpression) {
            return CommutativityPair(
                calleeName: name,
                leftArgName: leftRef.baseName.text,
                rightArgName: rightRef.baseName.text
            )
        }

        return nil
    }

    private struct CommutativityPair {
        let calleeName: String
        let leftArgName: String
        let rightArgName: String
    }

    // MARK: - Helpers (mirrored from AssertAfterTransformDetector)

    private static func collectBindings(
        in items: [CodeBlockItemSyntax]
    ) -> [String: ExprSyntax] {
        var bindings: [String: ExprSyntax] = [:]
        for item in items {
            guard case .decl(let decl) = item.item,
                  let varDecl = decl.as(VariableDeclSyntax.self),
                  let firstBinding = varDecl.bindings.first,
                  let identifierPattern = firstBinding.pattern.as(IdentifierPatternSyntax.self),
                  let initializer = firstBinding.initializer?.value else {
                continue
            }
            bindings[identifierPattern.identifier.text] = initializer
        }
        return bindings
    }

    private static func calleeName(of expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }
}

/// Output of `AssertSymmetryDetector.detect(in:)`. M2.3 wraps it in a
/// `LiftedSuggestion` whose cross-validation key matches
/// `CommutativityTemplate`'s production-side key for the same callee.
public struct DetectedCommutativity: Equatable, Sendable {

    /// The callee name for `f`. Source surface name; member-access call
    /// sites surface the *member* name (e.g. `set.union(other)` →
    /// `"union"`).
    public let calleeName: String

    /// The first argument's identifier name as written in the
    /// detector's "lhs" call site (the lexically-first call in
    /// collapsed form, or the lhs binding's init in explicit form).
    /// `f(a, b) == f(b, a)` → `leftArgName = "a"`.
    public let leftArgName: String

    /// The second argument's identifier name as written in the
    /// detector's "lhs" call site. `f(a, b) == f(b, a)` →
    /// `rightArgName = "b"`.
    public let rightArgName: String

    public let assertionLocation: SwiftInferCore.SourceLocation

    public init(
        calleeName: String,
        leftArgName: String,
        rightArgName: String,
        assertionLocation: SwiftInferCore.SourceLocation
    ) {
        self.calleeName = calleeName
        self.leftArgName = leftArgName
        self.rightArgName = rightArgName
        self.assertionLocation = assertionLocation
    }
}
