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

    /// The two count-law tests, or `""` when the callee is an actor's: the laws call `f` inside a
    /// synchronous closure, which an actor hop cannot enter.
    ///
    /// `keepsFirst` states C2 as equality, `f(value + value) == f(value)`. Only a keep-first body
    /// earns it, and only under strict equality: a dictionary-route dedupe returns its values in hash
    /// order, so two calls may list the same elements differently.
    static func dedupeCountLaws(
        callee: CalleeReference,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String,
        keepsFirst: Bool,
        equalityKind: EqualityKind = .strict
    ) -> String {
        guard callee.isolation != CalleeReference.actorReceiverIsolation else { return "" }
        let name = callee.identifierName
        let bare = callee.bareName
        let singleton = callee.isolated(
            "value.allSatisfy { element in \(callee.call("[element]")).count == 1 }"
        )
        let doubled = callee.call("value + value")
        let once = callee.call("value")
        let duplicate = callee.isolated(
            keepsFirst && equalityKind == .strict ? "\(doubled) == \(once)" : "\(doubled).count == \(once).count"
        )
        return makeTestStub(
            testFunctionName: "\(name)_keepsASingleton",
            seed: seed,
            generator: generator,
            propertyExpression: singleton,
            failureLabel: "\(bare)(_:) dropped a singleton (C1)",
            carrierType: typeName
        ) + "\n" + makeTestStub(
            testFunctionName: "\(name)_ignoresADuplicateOfEverything",
            seed: seed,
            generator: generator,
            propertyExpression: duplicate,
            failureLabel: "\(bare)(_:) kept a duplicate (C2)",
            carrierType: typeName
        )
    }
}
