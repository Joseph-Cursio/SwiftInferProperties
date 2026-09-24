import SwiftInferCore

/// The **measure** arm: a count, size or magnitude is never negative (`MeasureTemplate`).
///
/// It shares the totality arm's call machinery — any arity, the receiver drawn first, one
/// generator per argument — and differs only in what the property closure returns: the law is a
/// predicate on the result, so the closure returns `result >= 0` instead of discarding it.
/// `MeasureTemplate` admits only non-throwing, non-async, signed-integer-valued subjects, so there
/// is no `try?` to reason about and a negative is always representable.
///
/// Unlike totality, a failure here is a **counterexample**, not a crash: the check shrinks to the
/// input whose measure went negative — `capacity - used` past its boundary, `end - start` with the
/// ends swapped.
extension LiftedTestEmitter {

    public static func nonNegative(
        callee: CalleeReference,
        seed: SamplingSeed.Value,
        generators: [String],
        argumentTypes: [String] = [],
        failureLabel: String? = nil
    ) -> String {
        let isTuple = generators.count > 1
        let bind = isTuple
            ? tupleBinding(argumentTypes: argumentTypes, count: generators.count)
            : "value"
        let drawn = isTuple ? generators.indices.map { "args.\($0)" } : ["value"]
        let body = "return \(callee.call(drawn)) >= 0"
        return makeTestStubExpression(
            testFunctionName: "\(callee.bareName)_isNonNegative",
            seed: seed,
            sampleExpression: totalitySample(generators: generators),
            propertyExpression: "{ \(bind) in \(callee.isolated(body)) }",
            failureLabel: failureLabel ?? "\(callee.displaySignature) returned a negative measure"
        )
    }
}
