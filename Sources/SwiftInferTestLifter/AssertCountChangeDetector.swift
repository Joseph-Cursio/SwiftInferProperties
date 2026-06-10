import SwiftInferCore
import SwiftSyntax

/// PRD §7.3 "Assert-Count-Change → invariant preservation" detector.
/// Runs against a `SlicedTestBody` looking for the shape that asserts a
/// function preserves the `.count` of its collection-typed input:
/// `f(xs).count == xs.count`. M5 hard-codes the invariant keyPath to
/// `\.count` (M5 plan OD #2 default — broader keyPath generalization is
/// PRD §7.9 M9 expanded-outputs territory).
///
/// **Recognized shapes:**
/// - **Collapsed** (one assertion line):
///   ```
///   XCTAssertEqual(filter(xs).count, xs.count)
///   #expect(map(xs).count == xs.count)
///   ```
/// - **Explicit** (two-line let-then-assert):
///   ```
///   let result = transform(xs)
///   XCTAssertEqual(result.count, xs.count)
///   ```
///
/// **Single-callee + single-input invariant.** Exactly one side carries
/// the transformed `f(xs)`; the other side is the bare input `xs`. The
/// function call's first argument identifier matches the input side's
/// bare reference. `xs.count == xs.count` (no transform on either side)
/// and `f(xs).count == g(xs).count` (two callees, neither matches the
/// "bare input" shape) both reject.
///
/// **`.count` keyPath required.** Both sides must end in a `.count`
/// member access. `f(xs).first == xs.first` is rejected — that's a
/// different invariant (M9 territory).
///
/// **Tautology rejection.** Either both sides are bare `xs.count`
/// (no function call on either side), or both sides are
/// `f(...).count` with no bare-input side. The asymmetric "one
/// transformed, one bare" requirement rejects both.
///
/// **Out of scope for M5.2:** `#expect(once == twice)` explicit form
/// (mirrors M2.1's posture); `result.count` where `result`'s binding
/// initializer is itself another binding chain rather than a direct
/// function call; non-`.count` invariants (M9).
public enum AssertCountChangeDetector {

    public static func detect(in slice: SlicedTestBody) -> [DetectedCountInvariance] {
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

    /// `XCTAssertEqual(f(xs).count, xs.count)` /
    /// `#expect(f(xs).count == xs.count)` — one assertion-line shape.
    private static func detectCollapsed(assertion: AssertionInvocation) -> DetectedCountInvariance? {
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

        case .xctAssertTrue, .xctAssert, .xctAssertNotNil,
                .xctAssertLessThan, .xctAssertLessThanOrEqual,
                .xctAssertNotEqual, .xctAssertGreaterThan,
                .xctAssertGreaterThanOrEqual, .xctAssertFalse,
                .requireMacro:
            return nil
        }
    }

    private static func collapsedFromTwoArguments(
        lhs: ExprSyntax?,
        rhs: ExprSyntax?,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedCountInvariance? {
        guard let lhs, let rhs else {
            return nil
        }
        if let detected = collapsedCountChange(transform: lhs, input: rhs, location: location) {
            return detected
        }
        return collapsedCountChange(transform: rhs, input: lhs, location: location)
    }

    private static func collapsedFromEqualityExpression(
        _ expr: ExprSyntax,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedCountInvariance? {
        guard let operands = expr.equalityOperands else {
            return nil
        }
        return collapsedFromTwoArguments(lhs: operands.lhs, rhs: operands.rhs, location: location)
    }

    /// Try to interpret `transform` as `f(input).count` and `input` as
    /// `<inputName>.count`, where `inputName` matches the function
    /// call's first argument identifier.
    private static func collapsedCountChange(
        transform: ExprSyntax,
        input: ExprSyntax,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedCountInvariance? {
        guard let transformBase = countMemberBase(of: transform),
              let transformCall = transformBase.as(FunctionCallExprSyntax.self),
              let callee = transformCall.calledExpression.trailingIdentifierName,
              let transformArg = transformCall.arguments.first?.expression,
              let transformArgRef = transformArg.as(DeclReferenceExprSyntax.self),
              let inputBase = countMemberBase(of: input),
              let inputRef = inputBase.as(DeclReferenceExprSyntax.self),
              transformArgRef.baseName.text == inputRef.baseName.text else {
            return nil
        }
        return DetectedCountInvariance(
            calleeName: callee,
            inputBindingName: inputRef.baseName.text,
            assertionLocation: location
        )
    }

    // MARK: - Explicit shape

    /// `let result = f(xs); XCTAssertEqual(result.count, xs.count)` —
    /// two-statement shape. Both assertion sides are bare-ref `.count`;
    /// one side's binding is a `f(<inputName>)` initializer.
    private static func detectExplicit(
        assertion: AssertionInvocation,
        propertyRegion: [CodeBlockItemSyntax]
    ) -> DetectedCountInvariance? {
        guard assertion.kind == .xctAssertEqual,
              assertion.arguments.count == 2,
              let lhsBaseExpr = countMemberBase(of: assertion.arguments[0]),
              let lhsRef = lhsBaseExpr.as(DeclReferenceExprSyntax.self),
              let rhsBaseExpr = countMemberBase(of: assertion.arguments[1]),
              let rhsRef = rhsBaseExpr.as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let bindings = propertyRegion.bindingInitializers()
        if let detected = explicitCountChange(
            transformName: lhsRef.baseName.text,
            inputName: rhsRef.baseName.text,
            bindings: bindings,
            location: assertion.location
        ) {
            return detected
        }
        return explicitCountChange(
            transformName: rhsRef.baseName.text,
            inputName: lhsRef.baseName.text,
            bindings: bindings,
            location: assertion.location
        )
    }

    /// `transformName`'s binding initializer must be `f(inputName)`.
    private static func explicitCountChange(
        transformName: String,
        inputName: String,
        bindings: [String: ExprSyntax],
        location: SwiftInferCore.SourceLocation
    ) -> DetectedCountInvariance? {
        guard let transformInit = bindings[transformName],
              let call = transformInit.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.trailingIdentifierName,
              let firstArg = call.arguments.first?.expression,
              let firstArgRef = firstArg.as(DeclReferenceExprSyntax.self),
              firstArgRef.baseName.text == inputName else {
            return nil
        }
        return DetectedCountInvariance(
            calleeName: callee,
            inputBindingName: inputName,
            assertionLocation: location
        )
    }

    // MARK: - Helpers

    /// If `expr` is a `<base>.count` member access, return the `base`
    /// expression. Otherwise nil. M5 hard-codes the keyPath to `.count`
    /// (M5 plan OD #2 default).
    private static func countMemberBase(of expr: ExprSyntax) -> ExprSyntax? {
        guard let member = expr.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "count",
              let base = member.base else {
            return nil
        }
        return base
    }
}
