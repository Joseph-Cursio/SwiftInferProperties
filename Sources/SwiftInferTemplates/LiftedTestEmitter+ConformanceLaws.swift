import SwiftInferCore

/// Stub emitters for `codable-round-trip`, `binary-idempotence` and `dual-style-consistency` —
/// laws `verify` composes (`StrategistDispatchEmitter+CodableRoundTrip`, `+AlgebraicLaws`,
/// `+DualStyle`) and the accept path never wrote. Each states the same law as its composer.
extension LiftedTestEmitter {

    /// `decode(encode(x)) == x` through `JSONEncoder`/`JSONDecoder`. A codec that throws on a
    /// value it produced fails the law too: the property throws, and the check records it — the
    /// shape of the one real defect class this template has found (a decoder rejecting its own
    /// encoder's output).
    public static func codableRoundTrip(typeName: String, seed: SamplingSeed.Value, generator: String) -> String {
        let body = "let decoded = try JSONDecoder().decode(\(typeName).self, from: try JSONEncoder().encode(value)); "
            + "return decoded == value"
        return makeTestStub(
            testFunctionName: "\(identifierSafe(typeName))_roundTripsThroughJSON",
            seed: seed,
            generator: generator,
            propertyExpression: body,
            failureLabel: "\(typeName) does not round-trip through JSON",
            carrierType: typeName
        )
    }

    /// `op(x, x) == x` — combining a value with itself changes nothing (`union`, `max`, `merge`).
    public static func binaryIdempotence(
        callee: CalleeReference,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String,
        equalityKind: EqualityKind = .strict
    ) -> String {
        let property = callee.isolated(equalityExpression(
            lhs: callee.call(["value", "value"]),
            rhs: "value",
            kind: equalityKind
        ))
        return withApproximateEqualityHelper(
            makeTestStub(
                testFunctionName: "\(callee.bareName)_withItselfIsANoOp",
                seed: seed,
                generator: generator,
                propertyExpression: property,
                failureLabel: "\(callee.displaySignature) is not idempotent on equal operands",
                carrierType: typeName
            ),
            kind: equalityKind
        )
    }

    /// The two halves of a dual-style pair: `sorted()` / `sort()`, or `union(_:)` / `formUnion(_:)`.
    public struct DualStylePair: Sendable {
        public let nonMutating: CalleeReference
        public let mutating: CalleeReference
        /// Whether each half takes one operand beside the receiver (the `union` shape).
        public let takesOperand: Bool

        public init(nonMutating: CalleeReference, mutating: CalleeReference, takesOperand: Bool) {
            self.nonMutating = nonMutating
            self.mutating = mutating
            self.takesOperand = takesOperand
        }
    }

    /// The non-mutating half equals the mutating half applied to a copy:
    /// `x.sorted() == { var c = x; c.sort(); c }`. The `union` shape draws a second value as the
    /// operand, the same `a` and `b` passed to both halves.
    ///
    /// ⚠ **The operand pair is drawn tie-dense.** Most operand pairs disagree only on overlapping
    /// values — `union` and `symmetricDifference` coincide on disjoint sets — and two full-range
    /// draws almost never overlap. Planted on a fixture, a `union` rewritten as
    /// `symmetricDifference` passed this law until the draw was narrowed.
    public static func dualStyleConsistency(
        _ pair: DualStylePair,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        let receiver = pair.takesOperand ? "args.0" : "value"
        let operand = pair.takesOperand ? ["args.1"] : []
        let body = "var copy = \(receiver); \(pair.mutating.call(["copy"] + operand)); "
            + "return \(pair.nonMutating.call([receiver] + operand)) == copy"
        let binding = pair.takesOperand ? tupleBinding(argumentTypes: [typeName, typeName], count: 2) : "value"
        return makeTestStubExpression(
            testFunctionName: "\(pair.nonMutating.bareName)_agreesWith_\(pair.mutating.bareName)",
            seed: seed,
            sampleExpression: totalitySample(
                generators: pair.takesOperand ? [tieDense(generator), tieDense(generator)] : [generator]
            ),
            propertyExpression: "{ \(binding) in \(pair.nonMutating.isolated(body)) }",
            failureLabel: "\(pair.nonMutating.displaySignature) disagrees with \(pair.mutating.displaySignature)"
        )
    }
}
