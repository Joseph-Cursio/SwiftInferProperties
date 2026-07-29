import SwiftInferCore
import SwiftSyntax

/// A test asserting that a function agrees with a **reference computation** —
/// the test-side half of the differential / oracle family.
///
///     XCTAssertEqual(mySort(input), input.sorted())
///     #expect(myParse(text) == referenceParse(text))
///
/// ## Why this detector exists
///
/// TestLifter had six detectors and every one was keyed to a template the
/// catalog already shipped, so it could corroborate laws it already knew and
/// saw nothing else. `mySort(x) == x.sorted()` is the canonical miss: a human
/// wrote down an invariant, decided it holds for all inputs, and expressed it
/// executably — evidence strictly better than any naming heuristic — and the
/// tool discarded it because no template named the shape.
///
/// `DifferentialTemplate` now names it, which is what unblocks this detector:
/// a lifted record needs a template to promote into.
///
/// ## The shape, and how it is told apart from the other five
///
/// All the equality-shaped detectors look at `assertEqual(A, B)`. What
/// separates them is the relationship between the two sides:
///
/// | detector | shape |
/// |---|---|
/// | round-trip | one side is the **bare input** — `g(f(x)) == x` |
/// | double-apply (idempotence) | **same callee** both sides — `f(f(x)) == f(x)` |
/// | symmetry (commutativity) | same callee, **swapped arguments** |
/// | **reference equivalence** | **different callees**, shared input, neither side bare |
///
/// So the gate is: both sides are calls, the callee names differ, and some
/// identifier appears on both sides. That last condition is what makes it a
/// comparison *of two computations over one input* rather than two unrelated
/// values that happen to be equal in this example.
///
/// ## Which side is the subject
///
/// The law runs in one direction — a counterexample blames the implementation,
/// not the oracle — so the record has to say which is which.
///
/// The rule: if exactly one side is a **method call on the shared input**
/// (`input.sorted()`) and the other **takes the input as an argument**
/// (`mySort(input)`), the latter is the subject. A method on the input reads as
/// the library's answer; a function you passed the input to reads as yours.
/// When both sides have the same form the detector still records the pair, with
/// the first as subject, and the emitted caveat says the direction is a guess.
public enum AssertReferenceEquivalenceDetector {

    public static func detect(in slice: SlicedTestBody) -> [DetectedReferenceEquivalence] {
        guard let assertion = slice.assertion,
              let (lhs, rhs) = equalityOperands(of: assertion) else {
            return []
        }
        let bindings = slice.propertyRegion.bindingInitializers()
        guard let left = resolve(lhs, bindings: bindings),
              let right = resolve(rhs, bindings: bindings),
              left.callee != right.callee else {
            return []
        }
        // A shared identifier is what makes this one comparison rather than two
        // unrelated values. Without it, `f(a) == g(b)` is an example, not a law.
        guard let shared = left.inputs.intersection(right.inputs).min() else {
            return []
        }
        let (subject, reference) = orient(left, right)
        return [
            DetectedReferenceEquivalence(
                subjectCallee: subject.callee,
                referenceCallee: reference.callee,
                sharedInput: shared,
                directionIsCertain: subject.takesInputAsArgument && reference.isMethodOnInput,
                location: assertion.location
            )
        ]
    }

    /// One side of the assertion, reduced to what the law needs.
    struct Operand {
        let callee: String
        /// Identifiers this side reads — arguments plus, for a method call, the
        /// receiver.
        let inputs: Set<String>
        /// `mySort(input)` — the input arrived as an argument.
        let takesInputAsArgument: Bool
        /// `input.sorted()` — the input is the receiver.
        let isMethodOnInput: Bool
    }

    private static func equalityOperands(
        of assertion: AssertionInvocation
    ) -> (ExprSyntax, ExprSyntax)? {
        switch assertion.kind {
        case .xctAssertEqual:
            guard assertion.arguments.count >= 2 else { return nil }
            return (assertion.arguments[0], assertion.arguments[1])

        case .expectMacro, .requireMacro:
            guard let first = assertion.arguments.first,
                  let operands = first.equalityOperands else { return nil }
            return (operands.lhs, operands.rhs)

        default:
            return nil
        }
    }

    /// Reduce an operand to an `Operand`, following one level of `let` binding
    /// so the two-statement form is reached as well as the inline one:
    ///
    ///     let mine = mySort(input)
    ///     XCTAssertEqual(mine, input.sorted())
    private static func resolve(
        _ expression: ExprSyntax,
        bindings: [String: ExprSyntax]
    ) -> Operand? {
        if let call = expression.as(FunctionCallExprSyntax.self) {
            return operand(from: call)
        }
        if let name = expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
           let bound = bindings[name],
           let call = bound.as(FunctionCallExprSyntax.self) {
            return operand(from: call)
        }
        return nil
    }

    private static func operand(from call: FunctionCallExprSyntax) -> Operand? {
        guard let callee = call.calledExpression.trailingIdentifierName else { return nil }
        var inputs: Set<String> = []
        var takesInputAsArgument = false
        for argument in call.arguments {
            if let name = argument.expression.as(DeclReferenceExprSyntax.self)?.baseName.text {
                inputs.insert(name)
                takesInputAsArgument = true
            }
        }
        // `input.sorted()` — the receiver is the operand's real input.
        var isMethodOnInput = false
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let receiver = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text {
            inputs.insert(receiver)
            isMethodOnInput = true
        }
        guard !inputs.isEmpty else { return nil }
        return Operand(
            callee: callee,
            inputs: inputs,
            takesInputAsArgument: takesInputAsArgument,
            isMethodOnInput: isMethodOnInput
        )
    }

    /// `(subject, reference)` — see the type's doc comment for the rule.
    private static func orient(_ left: Operand, _ right: Operand) -> (Operand, Operand) {
        if left.isMethodOnInput, right.takesInputAsArgument, !right.isMethodOnInput {
            return (right, left)
        }
        return (left, right)
    }
}

/// A detected "this function agrees with that reference computation" assertion.
public struct DetectedReferenceEquivalence: Sendable, Equatable {

    /// The implementation under test — a counterexample is its bug.
    public let subjectCallee: String
    /// The computation it is being checked against.
    public let referenceCallee: String
    /// The identifier both sides read.
    public let sharedInput: String
    /// Whether the subject/reference split was determined structurally (one
    /// side a method on the input, the other taking it as an argument) rather
    /// than by falling back to source order.
    public let directionIsCertain: Bool
    public let location: SwiftInferCore.SourceLocation

    public init(
        subjectCallee: String,
        referenceCallee: String,
        sharedInput: String,
        directionIsCertain: Bool,
        location: SwiftInferCore.SourceLocation
    ) {
        self.subjectCallee = subjectCallee
        self.referenceCallee = referenceCallee
        self.sharedInput = sharedInput
        self.directionIsCertain = directionIsCertain
        self.location = location
    }
}
