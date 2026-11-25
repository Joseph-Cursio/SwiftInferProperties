import SwiftInferCore

// `--fail-on-refutation` — the opt-in CI gate, split out of `SwiftInferCommand.Verify.swift` so
// the command shell stays a flag list and a dispatch. Pure functions of what a run returned, so
// the gate's meaning is tested without a subprocess.
extension SwiftInferCommand.Verify {

    /// Whether `--fail-on-refutation` turns a `--suggestion` run into a non-zero exit.
    ///
    /// **Refuted means a counterexample was found**: the primary law's `.defaultFails`, or a
    /// companion law that refutes (`CompanionLawOutcome.refutes`, which the evidence log already
    /// reads as a refutation that withholds promotion). Nothing else trips it:
    /// - `.error` is the instrument failing, not the property — a build failure or a crash says
    ///   nothing about whether the law holds;
    /// - `.edgeCaseAdvisory` is advisory by design (`docs/design/verify-edge-pass.md`): the edge
    ///   pass "cannot retract" the default pass's verdict, and a gate that failed on it would;
    /// - a decline (`not-a-candidate`, an unsupported template or carrier) throws before any
    ///   outcome exists, so it exits through its own error path, flag or no flag.
    ///
    /// `enabled: false` is always `false` — without the flag, verify's exit status is what it
    /// was before the flag existed.
    static func failsRefutationGate(enabled: Bool, run: VerifyRun) -> Bool {
        guard enabled else { return false }
        if case .defaultFails = run.outcome { return true }
        return run.companionLaws.contains(where: \.refutes)
    }

    /// Whether `--fail-on-refutation` turns an `--all-from-index` survey into a non-zero exit:
    /// any record refuted under the same rule as `failsRefutationGate(enabled:run:)`.
    ///
    /// The survey records every entry, so here the excluded outcomes are visible as records:
    /// `measured-error`, `architectural-coverage-pending` (every decline, `not-a-candidate`
    /// included) and `measured-edgeCaseAdvisory` never trip it, and an entry the `--template`
    /// filter skipped has no record at all.
    static func failsRefutationGate(enabled: Bool, records: [SurveyRecord]) -> Bool {
        guard enabled else { return false }
        return records.contains { record in
            record.outcome == .measuredDefaultFails
                || (record.companionLaws ?? []).contains(where: \.refutes)
        }
    }
}
