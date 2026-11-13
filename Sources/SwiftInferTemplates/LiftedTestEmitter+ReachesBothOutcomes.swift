import SwiftInferCore

/// The reach test a `predicate` stub carries after its totality law (#665 commit 4b, in the W form
/// that #724's re-take decided: `docs/measurements/predicate-reach-check-reopen.md`).
///
/// ## What it claims, and why it only warns
///
/// `_isTotal` passes whatever the predicate answers, so a green law over draws that only ever got
/// `false` says nothing about the inputs where the predicate returns `true`. The reach test re-draws
/// the law's own inputs and records a NOT APPLIED note for each answer none of them got. It is a
/// reach claim, not a law, and under W it records a **warning**: G was 58.9%, so about two predicate
/// files in five carry the note, and a constant-by-design predicate keeps it rightly. That is too
/// noisy to fail anyone's CI on (#665 §7's E bar is 80%).
///
/// ## It sees exactly what the census measured
///
/// It draws from `Xoshiro(seed:)` over the law's four seed words, one draw statement per argument
/// and the law's pairings in the law's order. That is `SwiftPropertyBasedBackend.check`'s own loop,
/// written out because `Seed.makeXoshiro()` is not public, the same move `guard-domain`'s coverage
/// pass makes. It calls the subject through `TotalityCall`, as the law does. And it runs after the law,
/// because a suite carrying a reach test is `@Suite(.serialized)` (`InteractiveTriage.wrappedFileContents`).
/// So it sees the subject after exactly the law's 100 calls, which is the census's `Again` reading
/// (`class_again`), the one #665 §9's crosscheck holds arm B's verdicts to.
///
/// **Without `.serialized`, Swift Testing runs the two at once**, and the census never saw that,
/// because every harness passes `--no-parallel`. A subject with unsynchronised shared state, the toy's
/// `Sightings.isFirstSighting`, then crashed the test process in 10 of 10 parallel runs, and a run that
/// finished could name either side. The law alone never raced. So a test that should only warn could
/// crash a green file (#724's amendment A2).
///
/// ## Its shape is fixed by the crosscheck
///
/// #665 §9 normalises a predicate stub by dropping the `// Reach:` header, the
/// `@Test func …_reachesBothOutcomes(` test and the `nonisolated private static func reachNote(`
/// helper (`scripts/predicate_outcome_reach.py`'s `strip_reach`), plus, since #724's amendment A2,
/// the suite's `@Suite(.serialized)` line. Any other difference from today's stub blocks, so every
/// addition lives in those four places. The helper holds the only
/// `#if compiler(>=6.3)`, measured lint-clean and warning-free on both toolchains (#665 N9). Before
/// 6.3, Swift Testing has no warning severity, so the note is recorded inside `withKnownIssue`,
/// which reports it without failing the test.
///
/// ⚠ **The guard reads the compiler, not the Testing library linked.** A test target that builds the
/// swift-testing package below 6.3 from source gets a 6.3+ compiler and an `Issue.record(_:severity:)`
/// that is still SPI there, so every predicate file in it stops compiling. #665 §7, which is not
/// amendable, fixes the W form as exactly this helper, so the case is recorded rather than changed.
/// No corpus package builds swift-testing from source.
extension LiftedTestEmitter {

    /// The reach test and its `reachNote` helper, to follow a predicate's `_isTotal` inside the suite.
    ///
    /// Only for a subject that neither throws nor is `async`: `PredicateTemplate` admits no other
    /// (#665 N5), and the answer is read as a plain `Bool`.
    /// - Parameter subjectLabel: the parsed signature the note names, never a constructed receiver's
    ///   expression, for the reason `failureLabel` gives in the accept path.
    public static func reachesBothOutcomes(
        callee: CalleeReference,
        seed: SamplingSeed.Value,
        generators: [String],
        subjectLabel: String,
        inoutArguments: Set<Int> = [],
        pairings: [Int: DrawPairing] = [:]
    ) -> String {
        let lawTest = "\(callee.identifierName)_isTotal"
        let call = TotalityCall(
            callee: callee, drawCount: generators.count, isThrowing: false, isAsync: false,
            inoutArguments: inoutArguments
        )
        let seedWords = "0x\(hex(seed.stateA)), 0x\(hex(seed.stateB)), "
            + "0x\(hex(seed.stateC)), 0x\(hex(seed.stateD))"
        let loopBody = (reachDraws(generators: generators, pairings: pairings)
            + answerStatements(call, callee: callee)
            + ["reachedAnswers.insert(reachAnswer)"])
            .map { "        " + $0 }
            .joined(separator: "\n")
        // The law's call runs inside the backend's `async throws` property closure, so a constructed
        // receiver may carry a `try` (`try #require(…)` building a rule visitor's pattern). The reach test
        // makes that call in its own body, which must then throw too, or the file does not compile:
        // commit 5's crosscheck set aside two SwiftProjectLint stubs on exactly that. A throw can only
        // come from the receiver's own construction, which fails the law first.
        let effects = call.invocation.contains("try ") ? "async throws" : "async"
        let notes = [true, false]
            .map { reachNote(side: $0, subject: subjectLabel, lawTest: lawTest) }
            .joined(separator: "\n")
        return """


        @Test func \(callee.identifierName)_reachesBothOutcomes() \(effects) {
            // A reach claim, not a law. It re-draws \(lawTest)'s \(stubTrialCount) inputs, from its seed
            // and in its order, and notes an answer none of them got: the law's pass then says nothing
            // about the inputs that give it. It only warns. A predicate that no value of its argument
            // types can drive to the other answer keeps warning, and is right to.
            var rng = Xoshiro(seed: (\(seedWords)))
            var reachedAnswers: Set<Bool> = []
            for _ in 0 ..< \(stubTrialCount) {
        \(loopBody)
            }
        \(notes)
        }

        nonisolated private static func reachNote(_ text: String) {
            #if compiler(>=6.3)
            Issue.record("\\(text)", severity: .warning)
            #else
            withKnownIssue { Issue.record("\\(text)") }
            #endif
        }
        """
    }

    /// The law's draws, as statements in the loop: `totalitySample`'s, one per argument, then each
    /// pairing in argument order, so every draw takes the place in the random stream it takes in
    /// the law. A tuple is rebuilt as `args`, the name `TotalityCall` reads.
    static func reachDraws(generators: [String], pairings: [Int: DrawPairing]) -> [String] {
        guard generators.count > 1 else {
            return ["let value = (\(generators.first ?? "")).run(using: &rng)"]
        }
        let draws = generators.indices.map { index in
            "\(pairings[index] == nil ? "let" : "var") arg\(index) = (\(generators[index])).run(using: &rng)"
        }
        let paired = pairings.keys.sorted().compactMap { pairings[$0]?.statement(for: $0) }
        let slots = generators.indices.map { "arg\($0)" }.joined(separator: ", ")
        return draws + paired + ["let args = (\(slots))"]
    }

    /// `let reachAnswer = …`, isolated as the law isolates its call.
    ///
    /// The test's own names (`reachedAnswers`, `reachAnswer`) are ones no subject plausibly has: a
    /// local named like the subject would shadow it, and the file would not compile. `rng`, `value`
    /// and `args` are the law's names too, so the two cannot diverge.
    ///
    /// A global actor is a hop: the copies and the call run inside one `run { }`, which returns the
    /// answer. An actor receiver awaits the call alone. With no isolation, the copies are statements
    /// of their own.
    static func answerStatements(_ call: TotalityCall, callee: CalleeReference) -> [String] {
        let copies = call.copies.components(separatedBy: "; ").filter { !$0.isEmpty }
        guard let isolation = callee.isolation else {
            return copies + ["let reachAnswer = \(call.invocation)"]
        }
        // An actor receiver awaits the call alone: the copies read drawn values, which awaiting
        // would only warn about (`no 'async' operations occur within 'await' expression`).
        if isolation == CalleeReference.actorReceiverIsolation {
            return copies + [callee.isolated("let reachAnswer = \(call.invocation)")]
        }
        return ["let reachAnswer = \(callee.isolated(call.copies + "return \(call.invocation)"))"]
    }

    /// One side's `if !reachedAnswers.contains(…) { Self.reachNote(…) }`, the note's text in three literals.
    private static func reachNote(side: Bool, subject: String, lawTest: String) -> String {
        let clauses = NotApplied.reachSideClauses(side, subject: subject, lawTest: lawTest, trials: stubTrialCount)
            .map { "\"\(escapedForLiteral($0))\"" }
        let message = ([clauses[0]] + clauses.dropFirst().map { "    + \($0)" })
            .map { "            " + $0 }
            .joined(separator: "\n")
        return """
            if !reachedAnswers.contains(\(side)) {
                Self.reachNote(
        \(message)
                )
            }
        """
    }
}
