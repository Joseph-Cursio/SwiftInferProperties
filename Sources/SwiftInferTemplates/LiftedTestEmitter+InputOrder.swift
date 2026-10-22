import SwiftInferCore

/// The input-order-independence stub: the dictionary keys a sorted result holds, in order, for an
/// input and for its reversal (`InputOrderIndependenceTemplate`).
extension LiftedTestEmitter {

    /// Shares the totality arm's call machinery, and `sortedByKey`'s placement of the isolation hop:
    /// under a global actor the whole comparison runs inside it, because the elements' members are
    /// isolated too; an actor receiver awaits each call and compares outside.
    ///
    /// The second call reverses the first drawn value whose type is an array — a drawn receiver is
    /// not one — and reuses the rest. The comparison names no element type and needs only the key's
    /// `==`, which a dictionary key has. `nil` when nothing drawn is an array.
    public static func inputOrderIndependent(
        callee: CalleeReference,
        ordering: SortedOutput,
        seed: SamplingSeed.Value,
        generators: [String],
        argumentTypes: [String] = [],
        failureLabel: String
    ) -> String? {
        guard let key = ordering.dictionaryKeyMember,
              let reversedIndex = argumentTypes.firstIndex(where: InputOrderIndependenceTemplate.isArrayType),
              generators.indices.contains(reversedIndex) else {
            return nil
        }
        let isTuple = generators.count > 1
        let bind = isTuple ? tupleBinding(argumentTypes: argumentTypes, count: generators.count) : "value"
        let drawn = isTuple ? generators.indices.map { "args.\($0)" } : ["value"]
        var reversed = drawn
        reversed[reversedIndex] = "Array(\(drawn[reversedIndex]).reversed())"
        let member = ordering.member.map { ".\($0)" } ?? ""
        let keys = "\(member).map { $0.\(key) }"
        let original = callee.call(drawn) + keys
        let permutedCall = callee.call(reversed) + keys
        let body = callee.isolation == CalleeReference.actorReceiverIsolation
            ? "let output = \(callee.isolated(original)); "
                + "let fromReversed = \(callee.isolated(permutedCall)); return output == fromReversed"
            : callee.isolated("return \(original) == \(permutedCall)")
        return makeTestStubExpression(
            testFunctionName: "\(callee.identifierName)_isIndependentOfInputOrder",
            seed: seed,
            sampleExpression: totalitySample(generators: generators),
            propertyExpression: "{ \(bind) in \(body) }",
            failureLabel: failureLabel
        )
    }
}
