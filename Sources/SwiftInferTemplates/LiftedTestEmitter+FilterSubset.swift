import SwiftInferCore

/// The `filter-subset` arm: a named filter returns only elements it was handed (#476, #468).
///
/// ## The law is spelled with `contains`, not with `Set`
///
/// `Set(result).isSubset(of: Set(haystack))` is the obvious rendering and needs the element to be
/// **`Hashable`**. `result.allSatisfy { haystack.contains($0) }` states the identical law — every
/// returned element was in the input — and needs only **`Equatable`**, which is a strictly weaker
/// requirement satisfied by strictly more element types. Since the two cannot disagree, the weaker
/// constraint is chosen, and no reach is spent on a conformance the law does not need.
///
/// An empty result is vacuously a subset, which is correct and not an accident of the spelling.
///
/// ## Every subject is synchronous, non-throwing and non-mutating
///
/// Not a simplification — `FilterSubsetTemplate.isFilter` gates on all three, so no reachable
/// subject is any of them and carrying `isThrowing` / `isAsync` parameters here would be dead
/// arguments describing a shape that cannot arrive. **Isolation is the exception** and is handled:
/// `filterTemplates` in the corpus is a method on a SwiftUI `View`, so `callee.isolated(_:)` wraps
/// the body in the actor hop. That hop takes a *synchronous* closure, which this body is.
///
/// ## The draw is an array per collection argument, over `0 ... 8`
///
/// The generator this arm is handed is for the **element** type, wrapped in the kit's instance
/// `.array(of:)` — the idiom `composeHomomorphismPass` and `idempotence-lifted` already use, and
/// the one that exists in every language mode (there is no static `Gen.array`). Asking the
/// resolver for `[Violation]` outright answers `.todo`, because the universe holds a shape named
/// `Violation` and none named `[Violation]`.
///
/// **`0 ...` rather than `1 ...`, deliberately.** The empty input is where a filter that returns a
/// default, a sentinel or a fallback row gives itself away — the single most likely way this law
/// fails — so the draw has to be able to produce it.
extension LiftedTestEmitter {

    /// One filter-subset call: the subject, one generator per argument it needs, and which of
    /// those arguments is the collection the result must be drawn from.
    ///
    /// Bundled rather than passed loose because the arm would otherwise exceed SwiftLint's
    /// parameter ceiling, the same reason `strictWeakOrdering` takes its passes as a list.
    public struct FilterSubsetCall: Sendable {

        /// The subject, spelled the way a stub must call it.
        public let callee: CalleeReference

        /// One generator per argument the call needs, in application order — the receiver's first
        /// for an instance method. A generator for a collection argument already draws the
        /// collection; `arrayDraw(over:)` is what wraps an element generator to get there.
        public let generators: [String]

        /// Index into `generators` of the collection the result must be a subset of.
        public let haystackIndex: Int

        /// Whether the element type's `Equatable` conformance was left unproven, so the emitted
        /// file says so on its own line rather than failing to compile without explanation.
        public let conformanceIsUnverified: Bool

        public init(
            callee: CalleeReference,
            generators: [String],
            haystackIndex: Int,
            conformanceIsUnverified: Bool
        ) {
            self.callee = callee
            self.generators = generators
            self.haystackIndex = haystackIndex
            self.conformanceIsUnverified = conformanceIsUnverified
        }
    }

    /// An element generator wrapped so it draws arrays — `0 ... 8`, empty included.
    ///
    /// Parenthesised because a derived generator can be a multi-line expression carrying its own
    /// leading comment block, and `.array(of:)` has to attach to the whole of it.
    public static func arrayDraw(over element: String) -> String {
        "(\(element)).array(of: 0 ... 8)"
    }

    /// Emit a subset test for a named filter: every element it returns was in the collection it
    /// was handed.
    public static func filterSubset(_ call: FilterSubsetCall, seed: SamplingSeed.Value) -> String {
        let isTuple = call.generators.count > 1
        let bind = isTuple ? "args" : "value"
        let arguments = isTuple ? call.generators.indices.map { "args.\($0)" } : ["value"]
        let haystack = arguments[call.haystackIndex]
        let body = "let selected = \(call.callee.call(arguments)); "
            + "return selected.allSatisfy { \(haystack).contains($0) }"
        let note = call.conformanceIsUnverified
            ? "\n// The element type's `Equatable` conformance is NOT verified by this tool. If this file\n"
                + "// does not compile, that is what to check first — the law is sound, the check needs `==`."
            : ""
        return note + makeTestStubExpression(
            testFunctionName: "\(call.callee.bareName)_returnsOnlyElementsItWasGiven",
            seed: seed,
            sampleExpression: subsetSample(generators: call.generators),
            propertyExpression: "{ \(bind) in \(call.callee.isolated(body)) }",
            failureLabel: "\(call.callee.displaySignature) returned an element that was not in its input"
        )
    }

    /// One draw for a single argument; a tuple of draws, in argument order, for several.
    ///
    /// The same shape `totalitySample` emits, kept separate rather than shared because that one is
    /// `private` to its own arm and folding them together would couple two laws whose only
    /// agreement is incidental.
    private static func subsetSample(generators: [String]) -> String {
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
