import Foundation

/// The trap branch: recovering a **totality** counterexample from a run that died.
///
/// Split out of `VerifyResult.swift` when that file crossed SwiftLint's 400-line cap. The seam is
/// natural — every other rule in `parse` decodes markers from a run that *finished*, and this one
/// alone reconstructs a verdict from a run that did not.
extension VerifyResultParser {

    /// A trap that the **totality** law was hunting — a refutation, not an instrument failure.
    ///
    /// Every other verifiable law fails by assertion, so a trap in one of them means the generator
    /// drove the code somewhere the law was never evaluated: evidence about the domain, not about
    /// the property. `trapReason` says exactly that, and it is right for those twelve.
    ///
    /// The `predicate` law inverts it. Totality *is* "does not trap", so a trap is the counterexample
    /// — and reporting it as `.error` would file this composer's only real finding in the same bucket
    /// as a broken build. `composePredicatePass` prints the input before each call precisely so the
    /// last one survives; this reads it back.
    ///
    /// **Gated on the marker, not on the template.** `parse` is given no template, and threading one
    /// in to reach a single branch would couple the shared verdict decoder to the catalog. The
    /// marker is emitted by exactly one composer, so its presence is the same fact — and a stub that
    /// does not hunt traps cannot accidentally claim one.
    ///
    /// `inverseResult` carries the runtime's own message when it reached stderr, because "which
    /// trap" is the first thing a reader asks and the generic reason string would otherwise be the
    /// only place it appeared.
    static func totalityRefutation(
        from output: VerifierSubprocess.Output,
        lines: [String]
    ) -> VerifyOutcome? {
        guard trapReason(from: output) != nil,
              let input = value(forMarker: "VERIFY_TRIAL_INPUT:", in: lines)
        else { return nil }

        let trial = Int(value(forMarker: "VERIFY_TRIAL_INDEX:", in: lines) ?? "") ?? -1
        let runtimeMessage = output.stderr
            .split(separator: "\n")
            .first { $0.contains("Swift runtime failure") || $0.contains("Fatal error") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return .defaultFails(
            trial: trial,
            input: input,
            forwardResult: "trapped",
            inverseResult: runtimeMessage ?? "(runtime message not captured)",
            shrunk: nil,
            shrinkSteps: 0
        )
    }
}
