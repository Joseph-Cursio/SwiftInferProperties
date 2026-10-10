import SwiftInferCore

/// The two range laws' stubs: a result inside its documented range (`DocumentedRangeTemplate`), and
/// an empty range selecting nothing (`EmptyRangeTemplate`).
extension LiftedTestEmitter {

    /// The documented-range arm. Shares the totality arm's call machinery — any arity, the receiver
    /// drawn first — and checks the result against the stated range as a `Double`, so one stub
    /// serves every numeric codomain and NaN and infinity fail it, which a comparison of the
    /// original type could let through.
    public static func withinDocumentedRange(
        callee: CalleeReference,
        range: DocumentedRange,
        seed: SamplingSeed.Value,
        generators: [String],
        argumentTypes: [String] = [],
        failureLabel: String
    ) -> String {
        let isTuple = generators.count > 1
        let bind = generators.isEmpty ? "_"
            : isTuple ? tupleBinding(argumentTypes: argumentTypes, count: generators.count) : "value"
        let drawn = generators.isEmpty ? []
            : isTuple ? generators.indices.map { "args.\($0)" } : ["value"]
        let bounds = "(\(range.lower)...\(range.upper) as ClosedRange<Double>)"
        // No `return`: the body is one expression, and SwiftLint's `implicit_return` flags the
        // spelled-out form in the emitted closure.
        let body = "\(bounds).contains(Double(\(callee.call(drawn))))"
        return makeTestStubExpression(
            testFunctionName: "\(callee.identifierName)_staysInDocumentedRange",
            seed: seed,
            sampleExpression: generators.isEmpty ? "{ _ in () }" : totalitySample(generators: generators),
            propertyExpression: "{ \(bind) in \(callee.isolated(body)) }",
            failureLabel: failureLabel
        )
    }

    /// The empty-range arm: one bound drawn, passed as both ends.
    public static func emptyRange(
        callee: CalleeReference,
        bound: (typeName: String, generator: String),
        seed: SamplingSeed.Value
    ) -> String {
        let body = "\(callee.call(["value", "value"])).isEmpty"
        return makeTestStub(
            testFunctionName: "\(callee.identifierName)_emptyRangeSelectsNothing",
            seed: seed,
            generator: bound.generator,
            propertyExpression: callee.isolated(body),
            failureLabel: "\(callee.displaySignature) selected something from an empty range",
            carrierType: bound.typeName
        )
    }
}
