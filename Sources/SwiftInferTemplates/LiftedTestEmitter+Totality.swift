import SwiftInferCore

/// The totality arm, split out of `LiftedTestEmitter.swift` when that file passed SwiftLint's
/// 400-line ceiling — the same move that produced `+Algebraic` and `+Generators`.
///
/// It sits apart for a reason beyond length: every other arm in that file **compares two values**
/// and therefore constrains the return type to `Equatable`. This one compares nothing, which is
/// both why it reaches subjects the others cannot and why none of its code resembles theirs.
extension LiftedTestEmitter {

    /// Emit a **totality** test stub: the subject must return or throw for every input its
    /// parameter type admits, and must never trap.
    ///
    /// ## The property closure returns `true` unconditionally, and that is the law
    ///
    /// A trap is not an error value — it kills the process. So there is nothing to compare and
    /// nothing to catch: reaching the `return true` *is* the evidence, and a violation surfaces
    /// as a crashed test run rather than as a recorded issue. `InputTotalityTemplate` says this
    /// plainly for the same reason the emitted comment does — *"a violation crashes the test
    /// process rather than shrinking to a tidy counterexample… it is what a trap is, and it is
    /// why fuzzers exist"* — so nobody reads a crashed run as a broken harness.
    ///
    /// ## `try?` is the law, not a shortcut
    ///
    /// The claim is *return **or throw***. A parser handed malformed bytes is entitled to throw;
    /// that is its contract. So a throwing subject is called with `try?` and its error discarded,
    /// and only a trap can fail the test. Swallowing the error would be wrong for any other law
    /// in this catalog and is exactly right for this one.
    ///
    /// ## It needs no `Equatable`, which is why it reaches what it reaches
    ///
    /// Every other arm compares two values and therefore needs the return type to be `Equatable`
    /// — the constraint that sends so many subjects to a `.todo` generator. Totality discards the
    /// result (`_ =`), so the return type is unconstrained. The generator still has to produce
    /// the *parameter* type, which is the only remaining gate.
    ///
    /// - Parameter isThrowing: whether the subject is declared `throws`.
    /// - Parameter isAsync: whether the subject is declared `async`.
    public static func total(
        callee: CalleeReference,
        seed: SamplingSeed.Value,
        generator: String,
        isThrowing: Bool,
        isAsync: Bool
    ) -> String {
        total(callee: callee, seed: seed, generators: [generator], isThrowing: isThrowing, isAsync: isAsync)
    }

    /// Totality at **any** application arity: one generator per argument the call needs, the
    /// receiver's first for an instance method.
    ///
    /// ## Why totality, alone in the catalog, takes every arity
    ///
    /// Every other arm composes or compares, so its arity is part of its law: `f(f(x))` is only
    /// defined when the law applies one argument. Totality does neither — it calls once and
    /// discards the result — so "returns or throws for every input" is equally well-formed for
    /// `parse(_:)`, `isNeighbor(_:of:)` and `graph.matchesSearch(node)`. Holding it to arity 1
    /// declined **497 entailed laws in the corpus funnel census, the largest single loss it
    /// measured** (#464), while verify's predicate composer already drew one value per parameter
    /// and one for the receiver.
    ///
    /// One generator renders exactly as the single-generator overload always did, so no existing
    /// stub changes shape. Two or more draw a tuple — the multi-line sample the determinism arm
    /// uses — and the call takes `args.0`, `args.1`, … in argument order.
    /// - Parameter argumentTypes: the drawn values' types, in argument order, used to ANNOTATE
    ///   the property closure's tuple parameter. Empty, or a count that disagrees with
    ///   `generators`, emits exactly what it emitted before — see `tupleBinding`.
    public static func total(
        callee: CalleeReference,
        seed: SamplingSeed.Value,
        generators: [String],
        isThrowing: Bool,
        isAsync: Bool,
        argumentTypes: [String] = []
    ) -> String {
        let testFunctionName = "\(callee.bareName)_isTotal"
        let isTuple = generators.count > 1
        let bind = isTuple
            ? tupleBinding(argumentTypes: argumentTypes, count: generators.count)
            : "value"
        var invocation = callee.call(isTuple ? generators.indices.map { "args.\($0)" } : ["value"])
        if isAsync { invocation = "await \(invocation)" }
        if isThrowing { invocation = "try? \(invocation)" }
        // `_ =` discards the result: the law is that we GOT one, not what it was.
        let body = "_ = \(invocation); return true"
        // **An async subject must not be wrapped in an actor hop.** `MainActor.run` takes a
        // *synchronous* `@MainActor` closure, so an `await` cannot appear inside one — and it does
        // not need to: awaiting an isolated async function from a nonisolated context performs the
        // hop by itself. Wrapping it would emit code that does not compile, which is the defect
        // #432 fixed in the other direction.
        let property = isAsync ? "{ \(bind) in \(body) }" : "{ \(bind) in \(callee.isolated(body)) }"
        return makeTestStubExpression(
            testFunctionName: testFunctionName,
            seed: seed,
            sampleExpression: totalitySample(generators: generators),
            propertyExpression: property,
            failureLabel: "\(callee.displaySignature) failed totality"
        )
    }

    /// One draw for a single generator; a tuple of draws, in argument order, for several.
    private static func totalitySample(generators: [String]) -> String {
        guard generators.count > 1 else {
            return "{ rng in (\(generators.first ?? "")).run(using: &rng) }"
        }
        let draws = generators.indices.map { index in
            "                    let arg\(index) = (\(generators[index])).run(using: &rng)"
        }
        let slots = generators.indices.map { "arg\($0)" }.joined(separator: ", ")
        return (["{ rng in"] + draws + ["                    return (\(slots))", "                }"])
            .joined(separator: "\n")
    }
}
