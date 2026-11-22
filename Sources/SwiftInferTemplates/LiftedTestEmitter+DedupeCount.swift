import SwiftInferCore

/// #671's count laws for a dedupe `f: [T] -> [T]` (SwiftInferProperties#711), emitted beside its
/// idempotence stub over the same generator and seed.
///
/// - **C1** `value.allSatisfy { f([$0]).count == 1 }`: a singleton survives. Fails a dedupe that
///   returns `[]`, which idempotence passes.
/// - **C2** `f(value + value).count == f(value).count`: a duplicate of everything adds nothing.
///   Fails a dedupe that stopped deduplicating (the identity), which idempotence also passes.
///
/// Measured on SwiftUMLBridge's `dedupe(relationships:)` (`fixtures/dedupe-count-law/kill-arm/`):
/// C1 kills both `[]` mutants, C2 kills the identity, and idempotence kills none. Neither law needs
/// the generator to draw a duplicate: C1 draws singletons out of `value`, and C2 builds its own
/// duplicate.
public extension LiftedTestEmitter {

    /// The two count-law tests.
    ///
    /// `keepsFirst` states C2 as equality, `f(value + value) == f(value)`. Only a keep-first body
    /// earns it, and only under strict equality: a dictionary-route dedupe returns its values in hash
    /// order, so two calls may list the same elements differently.
    ///
    /// An actor's callee is written as statements with an explicit `await` on each call, since
    /// `allSatisfy`'s closure is synchronous and cannot make one. An earlier version dropped both laws
    /// for an actor while the row still promised them.
    static func dedupeCountLaws(
        callee: CalleeReference,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String,
        keepsFirst: Bool,
        equalityKind: EqualityKind = .strict
    ) -> String {
        let singleton = callee.isolation == CalleeReference.actorReceiverIsolation
            ? "for element in value { if await \(callee.call("[element]")).count != 1 { return false } }; return true"
            : callee.isolated("value.allSatisfy { element in \(callee.call("[element]")).count == 1 }")
        let duplicate = statements(
            callee: callee,
            bindings: [("doubled", callee.call("value + value")), ("once", callee.call("value"))],
            returning: keepsFirst && equalityKind == .strict ? "doubled == once" : "doubled.count == once.count"
        )
        return makeTestStub(
            testFunctionName: "\(callee.identifierName)_keepsASingleton",
            seed: seed,
            generator: generator,
            propertyExpression: singleton,
            failureLabel: "\(callee.bareName)(_:) dropped a singleton (C1)",
            carrierType: typeName
        ) + "\n" + makeTestStub(
            testFunctionName: "\(callee.identifierName)_ignoresADuplicateOfEverything",
            seed: seed,
            generator: generator,
            propertyExpression: duplicate,
            failureLabel: "\(callee.bareName)(_:) kept a duplicate (C2)",
            carrierType: typeName
        )
    }

    /// Idempotence for a dictionary-route dedupe, stated without order: `f(f(value))` has as many
    /// elements as `f(value)`, and each of them is in `f(value)`.
    ///
    /// **Why not `f(f(value)) == f(value)`.** The body returns `Array(d.values)`, so the second call
    /// lists the same values in another dictionary's hash order. Measured by #734's review: a correct
    /// `byKey[word.lowercased()] = word` dedupe failed the strict law at an input with no duplicates,
    /// while this form held. It needs only the `==` the strict law needed.
    static func idempotentIgnoringOrder(
        callee: CalleeReference,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        makeTestStub(
            testFunctionName: "\(callee.identifierName)_isIdempotent",
            seed: seed,
            generator: generator,
            propertyExpression: statements(
                callee: callee,
                bindings: [("once", callee.call("value")), ("twice", callee.call("once"))],
                returning: "twice.count == once.count && twice.allSatisfy { element in once.contains(element) }"
            ),
            failureLabel: "\(callee.bareName)(_:) failed idempotence (ignoring order)",
            carrierType: typeName
        )
    }

    /// A property body that binds each call, then returns `result`, which calls nothing.
    ///
    /// An actor's calls are awaited one by one; a global actor's run in one hop; an unisolated
    /// callee's run as written.
    private static func statements(
        callee: CalleeReference, bindings: [(name: String, call: String)], returning result: String
    ) -> String {
        let awaited = callee.isolation == CalleeReference.actorReceiverIsolation
        let lets = bindings.map { "let \($0.name) = \(awaited ? "await " : "")\($0.call)" }
        let body = (lets + ["return \(result)"]).joined(separator: "; ")
        return awaited ? body : callee.isolated(body)
    }
}
