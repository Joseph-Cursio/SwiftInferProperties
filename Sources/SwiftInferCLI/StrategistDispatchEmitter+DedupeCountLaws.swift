import SwiftInferCore

/// #711 — #671's dedupe count laws as verify COMPANIONS of a dedupe's idempotence pass
/// (`CompanionLawOutcome`).
///
/// - **C1** every element of `value` survives alone: `f([x]).count == 1`. Fails a dedupe that
///   returns `[]`, which idempotence passes.
/// - **C2** a duplicate of everything adds nothing: `f(value + value) == f(value)` on the
///   keep-first Set route, counts only on the dictionary route (hash order). Fails a dedupe that
///   stopped deduplicating, which idempotence also passes.
///
/// The accepted stub writes both (`LiftedTestEmitter.dedupeCountLaws`), so verify checks both and
/// the two cannot disagree. Four rules keep them companions rather than a second verdict:
///
/// 1. **They run last, after both of idempotence's passes printed their verdicts**, spliced in
///    before the stub's final `exit(0)` (`withCompanionLaws`). A first version ran them inside the
///    composer, so the edge pass re-ran them, and a trap there turned idempotence's both-pass
///    verdict into an error (#734's second review). Where they are now, Pass 1's
///    `defaultGenerator` and `applyOnce` are back in scope, and they draw from the default
///    generator, as the accepted stub does.
/// 2. **They never `exit`.** A failure prints `VERIFY_DEFAULT_LAW_<law>_RESULT: FAIL` and the run
///    goes on, so the parser's verdict stays idempotence's. `VerifyResultParser.companionLaws`
///    reads them separately.
/// 3. **They draw from their own stream**, `companionRng`, seeded like `collisionBase`, so
///    nothing they draw moves the primary law's inputs or its replay.
/// 4. **Each law prints `_BEGIN` before it runs.** A law that begins and never reports trapped;
///    the parser names it and keeps idempotence's `.bothPass`
///    (`VerifyResultParser.verdictSurvivingTrappedCompanion`).
extension StrategistDispatchEmitter {

    /// `finalPass` (the edge pass, or its sentinel) with the companion laws spliced in before its
    /// final `exit(0)`, or `finalPass` unchanged when the entry has none: only an `idempotence`
    /// entry with a route, composed in the direct shape that binds `applyOnce` at top level (the
    /// only shape a `[T] -> [T]` dedupe reaches).
    static func withCompanionLaws(_ finalPass: String, inputs: Inputs, defaultPass: String) -> String {
        guard inputs.template == TemplateName.idempotence.rawValue, let body = inputs.dedupeBody,
              defaultPass.contains("let applyOnce: ("),
              let exit = finalPass.range(of: "exit(0)", options: .backwards) else {
            return finalPass
        }
        return finalPass.replacingCharacters(in: exit, with: dedupeCompanionLaws(body) + "\nexit(0)")
    }

    static func dedupeCompanionLaws(_ body: DedupeBody) -> String {
        let c2Mismatch = body.keepsFirst ? "doubled != once" : "doubled.count != once.count"
        return """
        // --- #711: #671's count laws, companions to idempotence: run last, never exit. ---
        var companionRng = Xoshiro(seed: seedTuple)
        print("VERIFY_DEFAULT_LAW_C1_BEGIN")
        var companionC1Failed = false
        for trial in 0 ..< trials where !companionC1Failed {
            let value = defaultGenerator.run(using: &companionRng)
            if let element = value.first(where: { applyOnce([$0]).count != 1 }) {
                companionC1Failed = true
                print("VERIFY_DEFAULT_LAW_C1_RESULT: FAIL")
                print("VERIFY_DEFAULT_LAW_C1_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_LAW_C1_INPUT: \\([element])")
                print("VERIFY_DEFAULT_LAW_C1_OUTPUT: \\(applyOnce([element]))")
            }
        }
        if !companionC1Failed { print("VERIFY_DEFAULT_LAW_C1_RESULT: PASS") }
        print("VERIFY_DEFAULT_LAW_C2_BEGIN")
        var companionC2Failed = false
        for trial in 0 ..< trials where !companionC2Failed {
            let value = defaultGenerator.run(using: &companionRng)
            let doubled = applyOnce(value + value)
            let once = applyOnce(value)
            if \(c2Mismatch) {
                companionC2Failed = true
                print("VERIFY_DEFAULT_LAW_C2_RESULT: FAIL")
                print("VERIFY_DEFAULT_LAW_C2_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_LAW_C2_INPUT: \\(value)")
                print("VERIFY_DEFAULT_LAW_C2_OUTPUT: \\(doubled) vs \\(once)")
            }
        }
        if !companionC2Failed { print("VERIFY_DEFAULT_LAW_C2_RESULT: PASS") }
        """
    }
}
