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
/// the two cannot disagree. Three rules keep them companions rather than a second verdict:
///
/// 1. **They run after idempotence printed PASS, and never `exit`.** A failure prints
///    `VERIFY_DEFAULT_LAW_<law>_RESULT: FAIL` and the run goes on, so the parser's verdict stays
///    idempotence's. `VerifyResultParser.companionLaws` reads them separately.
/// 2. **They draw from their own stream**, `companionRng`, seeded like `collisionBase`. The edge
///    pass re-runs this composer on the same `rng`, so draws taken from it would shift every
///    Pass-2 input and break replay.
/// 3. **Each law prints `_BEGIN` before it runs.** A law that begins and never reports trapped,
///    and the parser says so instead of reading a silent pass.
///
/// The edge pass re-runs the composer with `VERIFY_DEFAULT_` renamed `VERIFY_EDGE_`, so the laws
/// also run on the boundary recipe under `VERIFY_EDGE_LAW_*`. Those results are advisory.
extension StrategistDispatchEmitter {

    static func dedupeCompanionLaws(_ body: DedupeBody) -> String {
        let c2Mismatch = body.keepsFirst ? "doubled != once" : "doubled.count != once.count"
        return """

        // --- #711: #671's count laws, companions to idempotence. They never exit. ---
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
