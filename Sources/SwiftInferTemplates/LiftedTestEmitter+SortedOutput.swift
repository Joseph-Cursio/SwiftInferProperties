import SwiftInferCore

/// The sorted-output stub: the comparator a function sorts its result with, checked on every
/// adjacent pair of what it returns (`SortedOutputTemplate`).
extension LiftedTestEmitter {

    /// Shares the totality arm's call machinery — any arity, the receiver drawn first.
    ///
    /// The check is the comparator's own chain with a non-strict last step: for each key, a pair
    /// that differs must differ in the key's direction, and a pair equal on every key is in order.
    /// It names no element type, so it compiles for any result whose comparator compiled.
    ///
    /// ⚠ **Where the check runs depends on the isolation, and the first version got it wrong.**
    /// Under a global actor the whole check runs inside the hop: in a module with
    /// `.defaultIsolation(MainActor.self)` the ELEMENTS' properties are MainActor-isolated too, so
    /// reading `first.fileCount` outside `MainActor.run` does not compile — measured on
    /// SwiftFormatRuleStudio's `ImpactReport.from`. An actor receiver is the opposite case: its
    /// hop is a bare `await` at each statement's head, which the check's nested closure cannot take,
    /// and what an actor method returns is a `Sendable` value safe to read outside. So there, only
    /// the call is isolated.
    public static func sortedByKey(
        callee: CalleeReference,
        ordering: SortedOutput,
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
        let member = ordering.member.map { ".\($0)" } ?? ""
        let call = callee.call(drawn) + member
        let check = "return zip(output, output.dropFirst()).allSatisfy { first, second in "
            + inOrderChain(ordering.keys) + " }"
        let body = callee.isolation == CalleeReference.actorReceiverIsolation
            ? "let output = \(callee.isolated(call)); \(check)"
            : callee.isolated("let output = \(call); \(check)")
        return makeTestStubExpression(
            testFunctionName: "\(callee.identifierName)_isSortedByItsComparator",
            seed: seed,
            sampleExpression: generators.isEmpty ? "{ _ in () }" : totalitySample(generators: generators),
            propertyExpression: "{ \(bind) in \(body) }",
            failureLabel: failureLabel
        )
    }

    /// `if first.k != second.k { return first.k > second.k }; …; return first.z <= second.z`.
    static func inOrderChain(_ keys: [SortKey]) -> String {
        guard let last = keys.last else { return "true" }
        let ties = keys.dropLast().map { key in
            "if first.\(key.path) != second.\(key.path) { "
                + "return first.\(key.path) \(key.ascending ? "<" : ">") second.\(key.path) }; "
        }
        return ties.joined()
            + "return first.\(last.path) \(last.ascending ? "<=" : ">=") second.\(last.path)"
    }
}
