import SwiftInferCore
import SwiftSyntax

/// PRD §7.9 row M7 + §4.1 "Counter-signal: asymmetric assertion".
/// Scans test bodies for negative-form assertions that contradict
/// candidate positive properties. Each detection produces a
/// `LiftedCounterSignal` keyed on the same `CrossValidationKey`
/// shape the positive detectors use.
///
/// **Recognized shapes** (all collapsed; explicit two-binding forms
/// deferred to a future widening if a real corpus needs them):
/// - **Round-trip negative:** `XCTAssertNotEqual(decode(encode(x)), x)`
///   / `#expect(decode(encode(x)) != x)`. Single-arg outer + single-
///   arg inner; both `f`s differ; argument matches the bare side.
/// - **Idempotence negative:** `XCTAssertNotEqual(f(f(x)), f(x))` /
///   `#expect(...)`. Same-callee outer + inner; argument matches.
/// - **Commutativity negative:** `XCTAssertNotEqual(f(a, b), f(b, a))`
///   / `#expect(...)`. Free / static call shape only (instance-method
///   shape `a.f(b)` deferred).
/// - **Monotonicity negative (anti-monotonicity):**
///   `XCTAssertLessThan(a, b); XCTAssertGreaterThan(f(a), f(b))` /
///   `#expect(a < b); #expect(f(a) > f(b))`. Strict `>` only per M7
///   plan OD #3 (mirror of M5.1's strict `<` precondition + `<=`/`<`
///   result).
/// - **Count-invariance negative:**
///   `XCTAssertNotEqual(f(xs).count, xs.count)` / `#expect(...)`.
/// - **Reduce-equivalence negative:**
///   `XCTAssertNotEqual(xs.reduce(s, op), xs.reversed().reduce(s, op))`
///   / `#expect(...)`. Same-collection / same-seed / same-op invariants
///   enforced; method-chain `xs.reduce(_:_:)` only.
///
/// **Single-callee invariant** carried over from each positive
/// detector — a counter-signal targeting the wrong callee would be
/// noise. Tautologies (no asymmetric form) reject as no-ops.
///
/// **File split.** The per-pattern detection functions for the M5
/// patterns (monotonicity / count-invariance / reduce-equivalence)
/// live in `AsymmetricAssertionDetector+M5Patterns.swift` to keep this
/// file under SwiftLint's 400-line file-length limit. The shared
/// helpers (`inequalityPair`, `calleeName`, `InequalityPair`) stay
/// in this file with `internal` visibility so the companion can use
/// them.
public enum AsymmetricAssertionDetector {

    public static func detect(in slice: SlicedTestBody) -> [DetectedAsymmetricAssertion] {
        guard let assertion = slice.assertion else {
            return []
        }
        var detections: [DetectedAsymmetricAssertion] = []
        if let detection = detectRoundTripNegative(assertion: assertion) {
            detections.append(detection)
        }
        if let detection = detectIdempotenceNegative(assertion: assertion) {
            detections.append(detection)
        }
        if let detection = detectCommutativityNegative(assertion: assertion) {
            detections.append(detection)
        }
        if let detection = detectMonotonicityNegative(
            conclusion: assertion,
            candidatePreconditions: slice.setup + slice.propertyRegion
        ) {
            detections.append(detection)
        }
        if let detection = detectCountInvarianceNegative(assertion: assertion) {
            detections.append(detection)
        }
        if let detection = detectReduceEquivalenceNegative(assertion: assertion) {
            detections.append(detection)
        }
        return detections
    }

    // MARK: - Round-trip negative — `XCTAssertNotEqual(decode(encode(x)), x)`

    private static func detectRoundTripNegative(
        assertion: AssertionInvocation
    ) -> DetectedAsymmetricAssertion? {
        guard let pair = inequalityPair(in: assertion) else {
            return nil
        }
        if let detected = roundTripNegativePair(transformed: pair.lhs, original: pair.rhs) {
            return detected
        }
        return roundTripNegativePair(transformed: pair.rhs, original: pair.lhs)
    }

    private static func roundTripNegativePair(
        transformed: ExprSyntax,
        original: ExprSyntax
    ) -> DetectedAsymmetricAssertion? {
        guard let outerCall = transformed.as(FunctionCallExprSyntax.self),
              let outerName = calleeName(of: outerCall.calledExpression),
              let outerArg = outerCall.arguments.first?.expression,
              let innerCall = outerArg.as(FunctionCallExprSyntax.self),
              let innerName = calleeName(of: innerCall.calledExpression),
              outerName != innerName,
              let innerArg = innerCall.arguments.first?.expression,
              let innerInput = innerArg.as(DeclReferenceExprSyntax.self),
              let originalRef = original.as(DeclReferenceExprSyntax.self),
              originalRef.baseName.text == innerInput.baseName.text else {
            return nil
        }
        return .roundTrip(forwardCallee: innerName, backwardCallee: outerName)
    }

    // MARK: - Idempotence negative — `XCTAssertNotEqual(f(f(x)), f(x))`

    private static func detectIdempotenceNegative(
        assertion: AssertionInvocation
    ) -> DetectedAsymmetricAssertion? {
        guard let pair = inequalityPair(in: assertion) else {
            return nil
        }
        if let detected = idempotenceNegativePair(doubled: pair.lhs, single: pair.rhs) {
            return detected
        }
        return idempotenceNegativePair(doubled: pair.rhs, single: pair.lhs)
    }

    private static func idempotenceNegativePair(
        doubled: ExprSyntax,
        single: ExprSyntax
    ) -> DetectedAsymmetricAssertion? {
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
        return .idempotence(calleeName: outerName)
    }

    // MARK: - Commutativity negative — `XCTAssertNotEqual(f(a, b), f(b, a))`

    private static func detectCommutativityNegative(
        assertion: AssertionInvocation
    ) -> DetectedAsymmetricAssertion? {
        guard let pair = inequalityPair(in: assertion) else {
            return nil
        }
        guard let leftCall = pair.lhs.as(FunctionCallExprSyntax.self),
              let rightCall = pair.rhs.as(FunctionCallExprSyntax.self),
              let leftName = calleeName(of: leftCall.calledExpression),
              let rightName = calleeName(of: rightCall.calledExpression),
              leftName == rightName,
              leftCall.arguments.count == 2,
              rightCall.arguments.count == 2,
              let leftA = leftCall.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
              let leftB = leftCall.arguments.dropFirst().first?.expression
                .as(DeclReferenceExprSyntax.self),
              let rightA = rightCall.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
              let rightB = rightCall.arguments.dropFirst().first?.expression
                .as(DeclReferenceExprSyntax.self),
              leftA.baseName.text == rightB.baseName.text,
              leftB.baseName.text == rightA.baseName.text,
              leftA.baseName.text != leftB.baseName.text else {
            return nil
        }
        return .commutativity(calleeName: leftName)
    }

    // MARK: - Shared inequality-pair extraction

    /// `XCTAssertNotEqual(lhs, rhs)` and `#expect(lhs != rhs)` both
    /// surface as a (lhs, rhs) pair the M7.0 negative-form detectors
    /// consume. **Internal** (not file-private) so the companion file
    /// `AsymmetricAssertionDetector+M5Patterns.swift` can use it.
    struct InequalityPair {
        let lhs: ExprSyntax
        let rhs: ExprSyntax
    }

    static func inequalityPair(
        in assertion: AssertionInvocation
    ) -> InequalityPair? {
        switch assertion.kind {
        case .xctAssertNotEqual:
            guard assertion.arguments.count >= 2,
                  let lhs = assertion.arguments.first,
                  let rhs = assertion.arguments.dropFirst().first else {
                return nil
            }
            return InequalityPair(lhs: lhs, rhs: rhs)
        case .expectMacro:
            guard let firstArg = assertion.arguments.first else {
                return nil
            }
            return inequalityFromExpectArg(firstArg)
        default:
            return nil
        }
    }

    private static func inequalityFromExpectArg(
        _ expr: ExprSyntax
    ) -> InequalityPair? {
        if let sequence = expr.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3,
                  let opExpr = elements[1].as(BinaryOperatorExprSyntax.self),
                  opExpr.operator.text == "!=" else {
                return nil
            }
            return InequalityPair(lhs: elements[0], rhs: elements[2])
        }
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           let opExpr = infix.operator.as(BinaryOperatorExprSyntax.self),
           opExpr.operator.text == "!=" {
            return InequalityPair(lhs: infix.leftOperand, rhs: infix.rightOperand)
        }
        return nil
    }

    /// Extract the base callee name from a call expression's
    /// `calledExpression`. Bare references and member-access tail names
    /// both surface. **Internal** so the companion file can use it.
    static func calleeName(of expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }
}
