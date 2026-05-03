import SwiftInferCore
import SwiftSyntax

/// PRD §7.3 "Assert-after-Transform → round-trip" detector. Runs
/// against the **property region** of a sliced test (not the raw body)
/// and surfaces round-trip patterns the M1.5 cross-validation wiring
/// will hash into a `LiftedSuggestion.identity`.
///
/// **Recognized shapes:**
/// - **Explicit** (three lines):
///   ```
///   let recovered = backward(intermediate)
///   let intermediate = forward(input)   // earlier in source
///   XCTAssertEqual(input, recovered)    // or (recovered, input)
///   ```
/// - **Collapsed** (one assertion line):
///   ```
///   XCTAssertEqual(backward(forward(input)), input)
///   #expect(backward(forward(input)) == input)
///   ```
///
/// Both shapes produce a `DetectedRoundTrip` carrying the forward and
/// backward callee names, the input binding identifier, and the
/// recovered binding identifier (`nil` for the collapsed form).
///
/// **Out of scope for M1:** receivers swapping mid-chain
/// (`a.encode(...)` → `b.decode(...)` where `a != b`); side-effecting
/// transforms; methods bound through computed properties; assertions
/// nested inside `if let` / `guard let` shadowing.
public enum AssertAfterTransformDetector {

    public static func detect(in slice: SlicedTestBody) -> [DetectedRoundTrip] {
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

    /// `XCTAssertEqual(backward(forward(x)), x)` /
    /// `#expect(backward(forward(x)) == x)` — one assertion-line shape.
    private static func detectCollapsed(assertion: AssertionInvocation) -> DetectedRoundTrip? {
        switch assertion.kind {
        case .xctAssertEqual:
            return collapsedFromTwoArguments(
                lhs: assertion.arguments.first,
                rhs: assertion.arguments.dropFirst().first,
                location: assertion.location
            )
        case .expectMacro:
            // `#expect(LHS == RHS)` — first argument is a binary
            // operator expression with `==` infix.
            guard let firstArg = assertion.arguments.first else {
                return nil
            }
            return collapsedFromEqualityExpression(firstArg, location: assertion.location)
        case .xctAssertTrue, .xctAssert, .xctAssertNotNil,
                .xctAssertLessThan, .xctAssertLessThanOrEqual, .requireMacro:
            return nil
        }
    }

    private static func collapsedFromTwoArguments(
        lhs: ExprSyntax?,
        rhs: ExprSyntax?,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedRoundTrip? {
        guard let lhs, let rhs else {
            return nil
        }
        if let detected = collapsedRoundTrip(call: lhs, otherSide: rhs, location: location) {
            return detected
        }
        return collapsedRoundTrip(call: rhs, otherSide: lhs, location: location)
    }

    private static func collapsedFromEqualityExpression(
        _ expr: ExprSyntax,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedRoundTrip? {
        // SwiftParser doesn't fold operator precedence at parse time —
        // `x == y` lands as a SequenceExprSyntax of three elements
        // (lhs, BinaryOperatorExprSyntax("=="), rhs) when the source
        // hasn't been put through OperatorTable.foldAll. Handle the
        // sequence shape directly; the folded `InfixOperatorExprSyntax`
        // shape is also accepted as a fallback.
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
    ) -> DetectedRoundTrip? {
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

    /// Try to interpret `call` as `backward(forward(x))` and `otherSide`
    /// as `x`. Returns `nil` if the shape doesn't match.
    private static func collapsedRoundTrip(
        call: ExprSyntax,
        otherSide: ExprSyntax,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedRoundTrip? {
        guard let outerCall = call.as(FunctionCallExprSyntax.self),
              let backwardName = calleeName(of: outerCall.calledExpression),
              let outerArg = outerCall.arguments.first?.expression,
              let innerCall = outerArg.as(FunctionCallExprSyntax.self),
              let forwardName = calleeName(of: innerCall.calledExpression),
              let innerArg = innerCall.arguments.first?.expression,
              let inputRef = innerArg.as(DeclReferenceExprSyntax.self),
              let otherRef = otherSide.as(DeclReferenceExprSyntax.self),
              inputRef.baseName.text == otherRef.baseName.text else {
            return nil
        }
        return DetectedRoundTrip(
            forwardCallee: forwardName,
            backwardCallee: backwardName,
            inputBindingName: inputRef.baseName.text,
            recoveredBindingName: nil,
            assertionLocation: location
        )
    }

    // MARK: - Explicit shape

    /// `let intermediate = forward(input); let recovered =
    /// backward(intermediate); XCTAssertEqual(input, recovered)` —
    /// three-statement shape.
    private static func detectExplicit(
        assertion: AssertionInvocation,
        propertyRegion: [CodeBlockItemSyntax]
    ) -> DetectedRoundTrip? {
        guard assertion.kind == .xctAssertEqual,
              assertion.arguments.count == 2,
              let lhsRef = assertion.arguments[0].as(DeclReferenceExprSyntax.self),
              let rhsRef = assertion.arguments[1].as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let bindings = collectBindings(in: propertyRegion)
        if let detected = explicitRoundTrip(
            inputName: lhsRef.baseName.text,
            recoveredName: rhsRef.baseName.text,
            bindings: bindings,
            location: assertion.location
        ) {
            return detected
        }
        // Try the swapped argument order — `XCTAssertEqual(recovered, input)`.
        return explicitRoundTrip(
            inputName: rhsRef.baseName.text,
            recoveredName: lhsRef.baseName.text,
            bindings: bindings,
            location: assertion.location
        )
    }

    /// `recovered`'s binding initializer is `backward(intermediate)`.
    /// `intermediate`'s binding initializer is `forward(input)`. The
    /// `input` name from the assertion side must match `forward`'s
    /// argument identifier. Returns the round-trip if all hold.
    private static func explicitRoundTrip(
        inputName: String,
        recoveredName: String,
        bindings: [String: ExprSyntax],
        location: SwiftInferCore.SourceLocation
    ) -> DetectedRoundTrip? {
        guard let recoveredInit = bindings[recoveredName],
              let outerCall = recoveredInit.as(FunctionCallExprSyntax.self),
              let backwardName = calleeName(of: outerCall.calledExpression),
              let intermediateArg = outerCall.arguments.first?.expression,
              let intermediateRef = intermediateArg.as(DeclReferenceExprSyntax.self),
              let intermediateInit = bindings[intermediateRef.baseName.text],
              let innerCall = intermediateInit.as(FunctionCallExprSyntax.self),
              let forwardName = calleeName(of: innerCall.calledExpression),
              let inputArg = innerCall.arguments.first?.expression,
              let inputRef = inputArg.as(DeclReferenceExprSyntax.self),
              inputRef.baseName.text == inputName else {
            return nil
        }
        return DetectedRoundTrip(
            forwardCallee: forwardName,
            backwardCallee: backwardName,
            inputBindingName: inputName,
            recoveredBindingName: recoveredName,
            assertionLocation: location
        )
    }

    // MARK: - Helpers

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
    /// `calledExpression`. Handles bare references (`encode(x)`) and
    /// member accesses (`encoder.encode(x)`). Returns `nil` for
    /// shapes M1 doesn't recognize (chained `a.b.c(x)`, subscripts,
    /// etc.).
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

/// Output of `AssertAfterTransformDetector.detect(in:)`. M1.4 hashes
/// `(forwardCallee, backwardCallee)` into a `LiftedSuggestion.identity`
/// matching `RoundTripTemplate`'s identity for the same function pair.
public struct DetectedRoundTrip: Equatable, Sendable {

    /// The "forward" half of the pair — `f` in `g(f(x)) == x`. Source
    /// surface name; member-access call sites surface the *member* name
    /// (e.g. `encoder.encode(x)` → `"encode"`).
    public let forwardCallee: String

    /// The "backward" half — `g`.
    public let backwardCallee: String

    /// The input identifier name — the value the round-trip closes
    /// over. Always set; `XCTAssertEqual(input, recovered)` shape and
    /// the collapsed shape both surface a concrete identifier here.
    public let inputBindingName: String

    /// The intermediate-bound recovered name — `let recovered = ...`.
    /// `nil` when the collapsed shape is detected (the assertion calls
    /// the backward function inline, no `let recovered` binding exists).
    public let recoveredBindingName: String?

    public let assertionLocation: SwiftInferCore.SourceLocation

    public init(
        forwardCallee: String,
        backwardCallee: String,
        inputBindingName: String,
        recoveredBindingName: String?,
        assertionLocation: SwiftInferCore.SourceLocation
    ) {
        self.forwardCallee = forwardCallee
        self.backwardCallee = backwardCallee
        self.inputBindingName = inputBindingName
        self.recoveredBindingName = recoveredBindingName
        self.assertionLocation = assertionLocation
    }
}
