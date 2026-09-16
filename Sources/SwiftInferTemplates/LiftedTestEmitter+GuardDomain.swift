import SwiftInferCore

/// The `guard-domain` arm: on the sub-domain a function's own early return carves out, the answer
/// is the expression that return names (#468).
///
/// ## The law is CONDITIONAL, and that is the whole design
///
/// Every other arm in this emitter states a law over the generator's entire range. This one states
/// it over a **sub-domain** — the half of the input space the guard singles out — and says nothing
/// outside it. So the property returns `true` for a draw that falls outside, which is correct and
/// is also how the test can pass while checking nothing.
///
/// **A conditional law that never applies is a green tick that means nothing.** The kit already
/// treats this as a first-class failure: `checkStrictWeakOrderingLaws` reports a law no drawn
/// triple ever exercised through `Issue.record` rather than passing it. Measured here, one
/// condition in the corpus is `self === other` — which independent draws reach approximately never
/// — so the coverage pass below is not defensive decoration, it is the difference between a result
/// and the `mimeType_idempotence` shape (#453): a law that passed 100 trials while being false,
/// because its counterexamples were outside the generator's reach.
///
/// The coverage pass re-draws from `Xoshiro(seed:)` over the **same four seed words** the check
/// uses, so it counts the draws the check will actually make rather than a different sample. It is
/// a plain loop because `Seed.makeXoshiro()` is not public and the four words are.
///
/// ## A pass is not a statement about the code
///
/// The guard satisfies the law by construction, so this can never find a bug that exists today —
/// it is a characterisation test that catches an *edit*. `Refutability.characterisationTemplates`
/// carries that fact to the emitted file's header, because a reader who takes a green tick here
/// for a correctness result has been misled by the tool.
extension LiftedTestEmitter {

    /// One guard-domain law, with every name already rebound to something the test can evaluate.
    ///
    /// Bundled for SwiftLint's parameter ceiling, as `strictWeakOrdering` bundles its passes.
    public struct GuardDomainCall: Sendable {

        /// The subject, spelled the way a stub must call it.
        public let callee: CalleeReference

        /// One generator per argument the call needs, in application order — the receiver's first.
        public let generators: [String]

        /// The sub-domain predicate over the drawn bindings, already negated for a `guard`: the
        /// early return fires when a `guard`'s condition FAILS and when an `if`'s holds, and
        /// getting that backwards inverts the law.
        public let domainPredicate: String

        /// What the early return yields, over the drawn bindings.
        public let returnedExpression: String

        /// The law as a sentence, for the coverage message — the reader's own line played back.
        public let statedLaw: String

        public init(
            callee: CalleeReference,
            generators: [String],
            domainPredicate: String,
            returnedExpression: String,
            statedLaw: String
        ) {
            self.callee = callee
            self.generators = generators
            self.domainPredicate = domainPredicate
            self.returnedExpression = returnedExpression
            self.statedLaw = statedLaw
        }
    }

    /// Emit a guard-domain characterisation test.
    ///
    /// **Both passes name the drawn values `arg0`, `arg1`, …**, so the sub-domain predicate has
    /// one spelling rather than two. The property closure rebinds the tuple to those names on its
    /// first lines; the coverage loop draws into them directly. A shared `@Sendable` closure would
    /// have needed its type written out, and the argument types are exactly what this arm does not
    /// always know.
    public static func guardDomain(_ call: GuardDomainCall, seed: SamplingSeed.Value) -> String {
        let slots = call.generators.indices.map { "arg\($0)" }
        let invocation = call.callee.call(slots)
        let seedWords = "0x\(hex(seed.stateA)), 0x\(hex(seed.stateB)), "
            + "0x\(hex(seed.stateC)), 0x\(hex(seed.stateD))"
        let draws = call.generators.indices
            .map { "            let arg\($0) = (\(call.generators[$0])).run(using: &coverageRNG)" }
            .joined(separator: "\n")
        return """

        @Test func \(call.callee.bareName)_holdsOnItsGuardedSubDomain() async {
            let backend = SwiftPropertyBasedBackend()
            let seed = Seed(
                stateA: 0x\(hex(seed.stateA)),
                stateB: 0x\(hex(seed.stateB)),
                stateC: 0x\(hex(seed.stateC)),
                stateD: 0x\(hex(seed.stateD))
            )

        \(coverageBlock(call, seedWords: seedWords, draws: draws))

        \(checkBlock(call, invocation: invocation))
        }
        """
    }

    /// The coverage pass: how many of the draws the check will make enter the sub-domain at all.
    ///
    /// Re-drawn from `Xoshiro(seed:)` over the SAME four words, so it counts the draws the check
    /// actually makes rather than a different sample. A plain loop because `Seed.makeXoshiro()` is
    /// not public and the four words are.
    private static func coverageBlock(
        _ call: GuardDomainCall,
        seedWords: String,
        draws: String
    ) -> String {
        """
            // COVERAGE. This law says nothing outside the sub-domain its guard carves out, so a
            // draw that never enters it passes without checking anything. Counted over the SAME
            // four seed words the check below uses, so these are the draws it will make.
            var coverageRNG = Xoshiro(seed: (\(seedWords)))
            var entered = 0
            for _ in 0 ..< 100 {
        \(draws)
                if \(call.domainPredicate) { entered += 1 }
            }
            if entered == 0 {
                Issue.record(
                    \"\"\"
                    NOT APPLIED — no draw entered the sub-domain in 100 trials, so the pass below \\
                    means nothing. The law is: \(call.statedLaw). Narrow the generator until it \\
                    reaches the sub-domain, or delete this test.
                    \"\"\"
                )
            }
        """
    }

    /// The law itself, silent outside the sub-domain its guard names.
    private static func checkBlock(_ call: GuardDomainCall, invocation: String) -> String {
        """
            let result = await backend.check(
                trials: 100,
                seed: seed,
                sample: \(guardDomainSample(call)),
                property: { drawn in
        \(bindings(call))
                    // Outside the sub-domain the law is silent, so there is nothing to check.
                    guard \(call.domainPredicate) else { return true }
                    return \(call.callee.isolated("\(invocation) == \(call.returnedExpression)"))
                }
            )
            if case let .failed(_, _, input, error) = result {
                Issue.record(
                    "\(escapedForLiteral(call.statedLaw)) — failed at input \\(input). \\(error?.message ?? "")"
                )
            }
        """
    }

    /// `text` safe to splice into a single-line Swift string literal.
    ///
    /// **The law is the author's own source text, and it contains quotes.** The template's
    /// documented example is `!(source.hasPrefix("---")) ⟹ …`, which closes the `Issue.record`
    /// literal three characters in and emits a file that does not parse. Caught by reading the
    /// first emitted stub against a real compiler rather than by a unit test, which is why the
    /// round trip is in the measurement and not only in the suite.
    ///
    /// The coverage message needs no escaping: it is a `"""` literal, where a bare quote is legal.
    static func escapedForLiteral(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The property closure's first lines: the drawn tuple destructured into `arg0`, `arg1`, … so
    /// the predicate and the call read the same way here as in the coverage loop.
    private static func bindings(_ call: GuardDomainCall) -> String {
        guard call.generators.count > 1 else { return "            let arg0 = drawn" }
        return call.generators.indices
            .map { "            let arg\($0) = drawn.\($0)" }
            .joined(separator: "\n")
    }

    /// One draw per argument, in application order.
    private static func guardDomainSample(_ call: GuardDomainCall) -> String {
        guard call.generators.count > 1 else {
            return "{ rng in (\(call.generators.first ?? "")).run(using: &rng) }"
        }
        let draws = call.generators.indices.map { index in
            "                let arg\(index) = (\(call.generators[index])).run(using: &rng)"
        }
        let slots = call.generators.indices.map { "arg\($0)" }.joined(separator: ", ")
        return (["{ rng in"] + draws + ["                return (\(slots))", "            }"])
            .joined(separator: "\n")
    }
}
