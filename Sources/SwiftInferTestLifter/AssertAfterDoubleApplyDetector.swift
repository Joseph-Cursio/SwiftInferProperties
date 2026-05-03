import SwiftInferCore
import SwiftSyntax

/// PRD §7.3 "Assert-after-Double-Apply → idempotence" detector. Runs
/// against the **property region** of a sliced test (not the raw body),
/// mirroring `AssertAfterTransformDetector`'s shape.
///
/// **Recognized shapes:**
/// - **Explicit** (three lines):
///   ```
///   let once = normalize(input)    // f(x)
///   let twice = normalize(once)    // f(f(x))
///   XCTAssertEqual(once, twice)    // or (twice, once)
///   ```
/// - **Collapsed** (one assertion line):
///   ```
///   XCTAssertEqual(normalize(normalize(input)), normalize(input))
///   #expect(normalize(normalize(input)) == normalize(input))
///   ```
///
/// **Single-callee invariant.** Outer `f`, inner `f`, and (in the explicit
/// form) both `let` bindings must reference the same callee name. A
/// `XCTAssertEqual(normalize(canonicalize(s)), canonicalize(s))` is
/// rejected — different callees aren't a double-apply, they're a
/// composition.
///
/// **Tautology rejection.** `XCTAssertEqual(f(s), f(s))` doesn't carry
/// the doubled side and is rejected at the first guard (the "doubled"
/// side's argument isn't a function call).
///
/// **Out of scope for M2.1:** `#expect(once == twice)` explicit form
/// (mirrors M1.3's posture — explicit form supports `XCTAssertEqual`
/// only); receivers swapping mid-chain; side-effecting transforms.
public enum AssertAfterDoubleApplyDetector {

    public static func detect(in slice: SlicedTestBody) -> [DetectedIdempotence] {
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

    /// `XCTAssertEqual(f(f(x)), f(x))` /
    /// `#expect(f(f(x)) == f(x))` — one assertion-line shape.
    private static func detectCollapsed(assertion: AssertionInvocation) -> DetectedIdempotence? {
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
                .xctAssertGreaterThanOrEqual, .requireMacro:
            return nil
        }
    }

    private static func collapsedFromTwoArguments(
        lhs: ExprSyntax?,
        rhs: ExprSyntax?,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedIdempotence? {
        guard let lhs, let rhs else {
            return nil
        }
        if let detected = collapsedDoubleApply(doubled: lhs, single: rhs, location: location) {
            return detected
        }
        return collapsedDoubleApply(doubled: rhs, single: lhs, location: location)
    }

    private static func collapsedFromEqualityExpression(
        _ expr: ExprSyntax,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedIdempotence? {
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
    ) -> DetectedIdempotence? {
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

    /// Try to interpret `doubled` as `f(f(x))` and `single` as `f(x)`
    /// where both `f`s match and both `x`s match.
    private static func collapsedDoubleApply(
        doubled: ExprSyntax,
        single: ExprSyntax,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedIdempotence? {
        guard let outerCall = doubled.as(FunctionCallExprSyntax.self),
              let outerName = calleeName(of: outerCall.calledExpression),
              let outerArg = outerCall.arguments.first?.expression,
              let innerCall = outerArg.as(FunctionCallExprSyntax.self),
              let innerName = calleeName(of: innerCall.calledExpression),
              outerName == innerName,
              let innerArg = innerCall.arguments.first?.expression,
              let innerInput = innerArg.as(DeclReferenceExprSyntax.self),
              let singleCall = single.as(FunctionCallExprSyntax.self),
              let singleName = calleeName(of: singleCall.calledExpression),
              singleName == outerName,
              let singleArg = singleCall.arguments.first?.expression,
              let singleInput = singleArg.as(DeclReferenceExprSyntax.self),
              singleInput.baseName.text == innerInput.baseName.text else {
            return nil
        }
        return DetectedIdempotence(
            calleeName: outerName,
            inputBindingName: innerInput.baseName.text,
            assertionLocation: location
        )
    }

    // MARK: - Explicit shape

    /// `let once = f(x); let twice = f(once); XCTAssertEqual(once, twice)`
    /// — three-statement shape.
    private static func detectExplicit(
        assertion: AssertionInvocation,
        propertyRegion: [CodeBlockItemSyntax]
    ) -> DetectedIdempotence? {
        guard assertion.kind == .xctAssertEqual,
              assertion.arguments.count == 2,
              let lhsRef = assertion.arguments[0].as(DeclReferenceExprSyntax.self),
              let rhsRef = assertion.arguments[1].as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let bindings = collectBindings(in: propertyRegion)
        if let detected = explicitDoubleApply(
            singleName: lhsRef.baseName.text,
            doubleName: rhsRef.baseName.text,
            bindings: bindings,
            location: assertion.location
        ) {
            return detected
        }
        return explicitDoubleApply(
            singleName: rhsRef.baseName.text,
            doubleName: lhsRef.baseName.text,
            bindings: bindings,
            location: assertion.location
        )
    }

    /// `doubleName`'s binding initializer is `f(singleName)`.
    /// `singleName`'s binding initializer is `f(<input>)`. The two `f`s
    /// must match.
    private static func explicitDoubleApply(
        singleName: String,
        doubleName: String,
        bindings: [String: ExprSyntax],
        location: SwiftInferCore.SourceLocation
    ) -> DetectedIdempotence? {
        guard let doubleInit = bindings[doubleName],
              let outerCall = doubleInit.as(FunctionCallExprSyntax.self),
              let outerName = calleeName(of: outerCall.calledExpression),
              let outerArg = outerCall.arguments.first?.expression,
              let outerArgRef = outerArg.as(DeclReferenceExprSyntax.self),
              outerArgRef.baseName.text == singleName,
              let singleInit = bindings[singleName],
              let innerCall = singleInit.as(FunctionCallExprSyntax.self),
              let innerName = calleeName(of: innerCall.calledExpression),
              innerName == outerName,
              let innerArg = innerCall.arguments.first?.expression,
              let innerInput = innerArg.as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        return DetectedIdempotence(
            calleeName: outerName,
            inputBindingName: innerInput.baseName.text,
            assertionLocation: location
        )
    }

    // MARK: - Helpers (mirrored from AssertAfterTransformDetector)

    /// Collect `let x = ...` bindings from the property region as a
    /// name → initializer-expr map.
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

    /// Extract the base callee name from a call expression's
    /// `calledExpression`. Bare references and member-access tail names
    /// both surface; deeper chains (`a.b.c(x)`) and subscripts return
    /// `nil`.
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

/// Output of `AssertAfterDoubleApplyDetector.detect(in:)`. M2.3 wraps
/// it in a `LiftedSuggestion` whose cross-validation key matches
/// `IdempotenceTemplate`'s production-side key for the same callee.
public struct DetectedIdempotence: Equatable, Sendable {

    /// The callee name for `f`. Source surface name; member-access call
    /// sites surface the *member* name (e.g. `s.normalized()` →
    /// `"normalized"`).
    public let calleeName: String

    /// The input identifier name — the value `f` was applied to. Always
    /// set; both shapes surface a concrete identifier here.
    public let inputBindingName: String

    public let assertionLocation: SwiftInferCore.SourceLocation

    public init(
        calleeName: String,
        inputBindingName: String,
        assertionLocation: SwiftInferCore.SourceLocation
    ) {
        self.calleeName = calleeName
        self.inputBindingName = inputBindingName
        self.assertionLocation = assertionLocation
    }
}
