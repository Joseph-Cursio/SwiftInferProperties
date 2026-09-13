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
        let testFunctionName = "\(callee.bareName)_isTotal"
        var invocation = callee.call("value")
        if isAsync { invocation = "await \(invocation)" }
        if isThrowing { invocation = "try? \(invocation)" }
        // `_ =` discards the result: the law is that we GOT one, not what it was.
        let body = "_ = \(invocation); return true"
        // **An async subject must not be wrapped in an actor hop.** `MainActor.run` takes a
        // *synchronous* `@MainActor` closure, so an `await` cannot appear inside one — and it does
        // not need to: awaiting an isolated async function from a nonisolated context performs the
        // hop by itself. Wrapping it would emit code that does not compile, which is the defect
        // #432 fixed in the other direction.
        let property = isAsync ? "{ value in \(body) }" : "{ value in \(callee.isolated(body)) }"
        return makeTestStubExpression(
            testFunctionName: testFunctionName,
            seed: seed,
            sampleExpression: "{ rng in (\(generator)).run(using: &rng) }",
            propertyExpression: property,
            failureLabel: "\(callee.displaySignature) failed totality"
        )
    }
}
